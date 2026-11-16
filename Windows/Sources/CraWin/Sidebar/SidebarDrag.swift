import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WindowsFoundation
import WinUI

/// What a press in the sidebar can start dragging: a row or favorite tile, or a space's icon.
enum SidebarDragSource: Equatable {
    case item(UUID)
    case space(UUID)
}

/// Where letting go would put it now (the Mac's SidebarListDrop, favorites slot and dock cell).
enum SidebarDragTarget: Equatable {
    case list(SidebarDropPlan.Drop)
    /// Among the favorite tiles, in this slot (counted with the dragged one in it).
    case favorites(slot: Int)
    /// Onto another space's icon: the item moves to that space.
    case space(UUID)
    /// A dragged space's icon lets go in this cell of the dock.
    case spaceCell(Int)
}

/// One item's row in the list as drawn: what SidebarDropPlan needs besides its frame.
struct SidebarRowMeta {
    let element: FrameworkElement
    let itemID: UUID
    let parent: UUID
    let index: Int
    let depth: Int
}

/// A drag in progress, and the overlay's parts (held here: WinRT wrappers made in Swift go away
/// once Swift lets go of them).
@MainActor
final class SidebarDragState {
    var source: SidebarDragSource?
    /// Where the press was, in screen pixels.
    var start = POINT()
    /// Past Windows' drag distance: the press is a drag now, not a click.
    var dragging = false
    var target: SidebarDragTarget?
    /// Puts back what the press did (a folder opened or closed by it).
    var undoPress: (() -> Void)?
    var timer: WinAppSDK.DispatcherQueueTimer?
    var lastTick = Date()
    /// The space icon the drag rests on, and since when (it comes forward after a while).
    var spaceHover: (id: UUID, since: Date)?

    let line = Border()
    let ring = WinUI.Ellipse()  // not GDI's Ellipse
    let outline = Border()
    let half = WinUI.Rectangle()  // not GDI's Rectangle
    let ghost = Border()
    let ghostText = TextBlock()

    var draggedItem: UUID? {
        guard dragging, case .item(let id)? = source else { return nil }
        return id
    }

    var draggedSpace: UUID? {
        guard dragging, case .space(let id)? = source else { return nil }
        return id
    }
}

/// Drag and drop in the sidebar, as on the Mac (SpaceListView, SpaceColumnView's favorites,
/// SpaceDockCell, the dock's reorder): a row moves before or after another, into a folder, makes
/// a split with a tab, joins the favorites or another space; a space's icon moves along the dock.
///
/// Rows are buttons that act on press (UI.button), so the drag is followed from Win32 rather than
/// XAML's pointer events, which the button keeps: a press on a row notes where it was, a timer
/// watches the mouse until it moves past Windows' drag distance (a drag) or is let go (a click,
/// already handled), and from then on the window holds the mouse, so no page sees it, until the
/// release lands the drop. Escape cancels it.
extension SidebarView {
    // Win32 numbers WinSDK leaves as macros.
    private static let leftButton: Int32 = 0x01, rightButton: Int32 = 0x02, escapeKey: Int32 = 0x1B
    private static let swapButtons: Int32 = 23, dragWidth: Int32 = 68, dragHeight: Int32 = 69  // SM_SWAPBUTTON, SM_CXDRAG, SM_CYDRAG
    /// The list scrolls while a drag is this close to its top or bottom, up to this fast (DIPs/s).
    private static let scrollBand = 48.0, scrollSpeed = 900.0
    /// A favorite tile's height and the gap between tiles (buildFavorites).
    private static let tileHeight = 44.0, tileGap = 6.0
    /// The insertion line's ring and stroke (SidebarListMetrics: 8 and 2, 92 % of the text colour).
    private static let ringSize = 8.0, lineWidth = 2.0

    func makeDragChrome() {
        let d = drag
        overlay.isHitTestVisible = false
        root.children.append(overlay)
        try? Grid.setRowSpan(overlay, 4)
        try? Canvas.setZIndex(overlay, 100)
        d.line.cornerRadius = CornerRadius(topLeft: 1, topRight: 1, bottomRight: 1, bottomLeft: 1)
        d.ring.width = Self.ringSize
        d.ring.height = Self.ringSize
        d.ring.strokeThickness = Self.lineWidth
        d.outline.borderThickness = Thickness(left: 1.5, top: 1.5, right: 1.5, bottom: 1.5)
        d.outline.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        d.half.strokeThickness = 1.25
        d.half.radiusX = 5
        d.half.radiusY = 5
        let dashes = DoubleCollection()
        dashes.append(4 / 1.25)
        dashes.append(3 / 1.25)
        d.half.strokeDashArray = dashes
        d.ghost.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        d.ghost.padding = Thickness(left: 10, top: 5, right: 10, bottom: 5)
        d.ghost.maxWidth = 220
        d.ghost.opacity = 0.92
        d.ghostText.fontSize = 13
        d.ghostText.textTrimming = .characterEllipsis
        d.ghost.child = d.ghostText
        let parts: [UIElement] = [d.half, d.outline, d.line, d.ring, d.ghost]
        for part in parts {
            part.visibility = .collapsed
            overlay.children.append(part)
        }
        favoritesCard.visibility = .collapsed
        favoritesCard.height = 36
        favoritesCard.margin = Thickness(left: 0, top: 0, right: 0, bottom: 8)
        favoritesCard.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        favoritesCard.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        root.children.append(favoritesCard)
        try? Grid.setRow(favoritesCard, 0)
    }

    /// Arc's "Drag to add Favorites" card stands in for an empty grid while a tab or split is
    /// dragged in a space that keeps favorites.
    func showFavoritesCard() {
        let space = store.focusedSpaceID(window: windowID)
        let shows = drag.draggedItem.map { id in
            favoriteTiles.isEmpty && !store.children(of: store.focusedSpace(window: windowID).favoritesContainerID).contains { $0.isTab || $0.isSplit }
                && SidebarDropPlan.favoritesAccept(id, space: space, store: store)
        } ?? false
        favoritesCard.visibility = shows ? .visible : .collapsed
        guard shows else { return }
        favoritesCard.borderBrush = palette.secondaryText
        favoritesCard.background = drag.target == .favorites(slot: 0) ? palette.selected : palette.tile
        let label = UI.text("Add to Favorites", size: 12, color: palette.secondaryText)
        label.horizontalAlignment = .center
        label.verticalAlignment = .center
        favoritesCard.child = label
    }

    /// Notes the row `item` just drew (at `index` in the list's children) for drops.
    func noteRow(_ item: SidebarItem, depth: Int, at index: Int) {
        guard index >= 0, index < list.children.count, let element = list.children[index] as? FrameworkElement,
              let parent = item.parentID else { return }
        let position = store.item(parent)?.children.firstIndex(of: item.id) ?? 0
        rowMeta.append(SidebarRowMeta(element: element, itemID: item.id, parent: parent, index: position, depth: depth))
        if item.id == drag.draggedItem { element.opacity = 0.4 }
    }

    // MARK: Following the mouse

    private static func buttonDown() -> Bool {
        GetAsyncKeyState(GetSystemMetrics(swapButtons) != 0 ? rightButton : leftButton) < 0
    }

    /// A row, tile or space icon was pressed: a drag starts if the mouse moves on before it is let
    /// go. `undo` puts back what the press itself did, should it become a drag.
    func dragPressed(_ source: SidebarDragSource, undo: (() -> Void)? = nil) {
        // Keys (Space, Return) press buttons too; only the mouse drags.
        guard Self.buttonDown(), drag.source == nil else { return }
        var p = POINT()
        guard GetCursorPos(&p) else { return }
        drag.source = source
        drag.start = p
        drag.dragging = false
        drag.target = nil
        drag.undoPress = undo
        drag.lastTick = Date()
        guard let queue = WinAppSDK.DispatcherQueue.getForCurrentThread(), let timer = try? queue.createTimer() else {
            drag.source = nil
            return
        }
        timer.interval = TimeSpan(duration: 16 * 10_000)
        timer.isRepeating = true
        timer.tick.addHandler { [weak self] _, _ in self?.dragTick() }
        try? timer.start()
        drag.timer = timer
    }

    private func dragTick() {
        guard drag.source != nil else { return endDrag() }
        let now = Date()
        let dt = min(now.timeIntervalSince(drag.lastTick), 0.05)
        drag.lastTick = now
        if !drag.dragging {
            // Let go before moving far: it was a click, which the button already took.
            guard Self.buttonDown() else { return endDrag() }
            var p = POINT()
            guard GetCursorPos(&p) else { return }
            guard abs(p.x - drag.start.x) > GetSystemMetrics(Self.dragWidth) / 2 || abs(p.y - drag.start.y) > GetSystemMetrics(Self.dragHeight) / 2
            else { return }
            beginDrag()
        }
        if GetAsyncKeyState(Self.escapeKey) < 0 { return endDrag() }
        guard Self.buttonDown() else {
            let target = drag.target
            let source = drag.source
            endDrag()
            if let source, let target { land(source, on: target) }
            return
        }
        updateTarget(dt: dt)
    }

    private func beginDrag() {
        drag.dragging = true
        drag.undoPress?()
        drag.undoPress = nil
        captureMouse()
        let text: String
        switch drag.source {
        case .item(let id)?: text = store.item(id).map(dragTitle) ?? ""
        case .space(let id)?: text = store.space(id).map { $0.emoji.isEmpty ? $0.title : "\($0.emoji)  \($0.title)" } ?? ""
        case nil: text = ""
        }
        drag.ghostText.text = text
        showFavoritesCard()
    }

    private func dragTitle(_ item: SidebarItem) -> String {
        if item.isSplit { return store.children(of: item.id).map(\.displayTitle).joined(separator: " | ") }
        return item.displayTitle.isEmpty ? "New Tab" : item.displayTitle
    }

    /// Stops following the mouse and takes the drag's marks away.
    func endDrag() {
        try? drag.timer?.stop()
        drag.timer = nil
        let wasDragging = drag.dragging
        drag.source = nil
        drag.dragging = false
        drag.target = nil
        drag.undoPress = nil
        drag.spaceHover = nil
        let parts: [UIElement] = [drag.line, drag.ring, drag.outline, drag.half, drag.ghost]
        for part in parts { part.visibility = .collapsed }
        guard wasDragging else { return }
        _ = ReleaseCapture()
        for row in rowMeta { row.element.opacity = 1 }
        for tile in favoriteTiles { tile.element.opacity = 1 }
        for cell in spaceCells { cell.element.opacity = 1 }
        showFavoritesCard()
    }

    // MARK: Where it would land

    private struct Frame {
        var x: Double, y: Double, width: Double, height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
        func contains(_ p: (x: Double, y: Double), slop: Double = 0) -> Bool {
            p.x >= x - slop && p.x < maxX + slop && p.y >= y - slop && p.y < maxY + slop
        }
    }

    /// An element's frame in the overlay's coordinates; nil while it isn't shown.
    private func frame(of element: FrameworkElement) -> Frame? {
        guard element.visibility == .visible, let t = try? element.transformToVisual(overlay),
              let o = try? t.transformPoint(WindowsFoundation.Point(x: 0, y: 0)) else { return nil }
        return Frame(x: Double(o.x), y: Double(o.y), width: element.actualWidth, height: element.actualHeight)
    }

    /// The pointer in the overlay's coordinates.
    private func pointerInOverlay() -> (x: Double, y: Double)? {
        guard let p = pointer(), let t = try? overlay.transformToVisual(nil),
              let o = try? t.transformPoint(WindowsFoundation.Point(x: 0, y: 0)) else { return nil }
        return (p.x - Double(o.x), p.y - Double(o.y))
    }

    private func updateTarget(dt: Double) {
        guard let p = pointerInOverlay() else { return }
        autoscroll(p, dt: dt)
        let target = target(at: p)
        if target != drag.target {
            drag.target = target
            if case .favorites? = target { showFavoritesCard() } else if favoritesCard.visibility == .visible { showFavoritesCard() }
        }
        hoverSpace(target)
        drawPreview(p)
    }

    private func target(at p: (x: Double, y: Double)) -> SidebarDragTarget? {
        let space = store.focusedSpaceID(window: windowID)
        if let id = drag.draggedSpace {
            // The dock: the cell under the pointer, by its column alone.
            let cells = spaceCells.compactMap { cell in frame(of: cell.element).map { (cell.id, $0) } }
            guard let bar = frame(of: spacesBar), p.y >= bar.y - 24, p.y < bar.maxY + 24,
                  let i = cells.firstIndex(where: { p.x < $0.1.maxX + 1 }) ?? (cells.isEmpty ? nil : cells.count - 1)
            else { return nil }
            return cells[i].0 == id ? nil : .spaceCell(i)
        }
        guard let id = drag.draggedItem, store.item(id) != nil else { return nil }
        // Another space's icon.
        for cell in spaceCells where cell.id != store.spaceID(ofItem: id) {
            if let f = frame(of: cell.element), f.contains(p) {
                return store.isIncognito(item: id) == store.isIncognito(space: cell.id) ? .space(cell.id) : nil
            }
        }
        // The favorites, or the card standing in for them.
        if let card = frame(of: favoritesCard), card.contains(p) { return .favorites(slot: 0) }
        if let grid = frame(of: favorites), grid.contains(p, slop: 4), SidebarDropPlan.favoritesAccept(id, space: space, store: store) {
            let columns = 4.0
            let cell = (grid.width - Self.tileGap * (columns - 1)) / columns
            let column = min(columns - 1, max(0, ((p.x - grid.x) / (cell + Self.tileGap)).rounded(.down)))
            let row = max(0, ((p.y - grid.y) / (Self.tileHeight + Self.tileGap)).rounded(.down))
            let resting = favoriteTiles.filter { $0.id != id }.count
            return .favorites(slot: min(resting, Int(row * columns + column)))
        }
        // The list.
        guard let viewport = frame(of: scroll), viewport.contains(p) else { return nil }
        let rows = rowMeta.compactMap { meta -> SidebarDropPlan.Row? in
            guard let f = frame(of: meta.element) else { return nil }
            return SidebarDropPlan.Row(itemID: meta.itemID, parent: meta.parent, index: meta.index, depth: meta.depth,
                                       minY: f.y, maxY: f.maxY, minX: f.x, maxX: f.maxX)
        }.sorted { $0.minY < $1.minY }
        let top = frame(of: list)?.y ?? viewport.y
        // The divider is 1 DIP with 6 above and below it (addDivider).
        let line = divider.flatMap(frame(of:))
        let layout = SidebarDropPlan.Layout(rows: rows, pinnedMinY: top, pinnedMaxY: line.map { $0.y - 6 } ?? top,
                                            todayMinY: line.map { $0.maxY + 6 } ?? top, rowSpacing: Double(list.spacing))
        return .list(SidebarDropPlan.resolve(dragged: id, at: p, layout: layout, space: space, store: store))
    }

    /// Resting on another space's icon brings that space forward, so the drop can go anywhere in it.
    private func hoverSpace(_ target: SidebarDragTarget?) {
        guard case .space(let id)? = target, id != store.focusedSpaceID(window: windowID) else {
            drag.spaceHover = nil
            return
        }
        guard let hover = drag.spaceHover, hover.id == id else {
            drag.spaceHover = (id, Date())
            return
        }
        if Date().timeIntervalSince(hover.since) >= SidebarDropPlan.spaceHoverDelay {
            store.focusSpace(id, window: windowID)
        }
    }

    /// Scrolls the list while the drag is near its top or bottom (the Mac's DragAutoscroller).
    private func autoscroll(_ p: (x: Double, y: Double), dt: Double) {
        guard drag.draggedItem != nil, let f = frame(of: scroll), p.x >= f.x, p.x < f.maxX else { return }
        let fromTop = p.y - f.y, fromBottom = f.maxY - p.y
        var speed = 0.0
        if fromTop >= 0, fromTop < Self.scrollBand { speed = -Self.scrollSpeed * (1 - fromTop / Self.scrollBand) }
        if fromBottom >= 0, fromBottom < Self.scrollBand { speed = Self.scrollSpeed * (1 - fromBottom / Self.scrollBand) }
        guard speed != 0 else { return }
        let offset = min(max(0, scroll.verticalOffset + speed * dt), scroll.scrollableHeight)
        if offset != scroll.verticalOffset { _ = try? scroll.changeView(nil, offset, nil, true) }
    }

    // MARK: Drawing it

    private func place(_ element: FrameworkElement, x: Double, y: Double, width: Double? = nil, height: Double? = nil) {
        try? Canvas.setLeft(element, x)
        try? Canvas.setTop(element, y)
        if let width { element.width = max(0, width) }
        if let height { element.height = max(0, height) }
        element.visibility = .visible
    }

    private func drawPreview(_ p: (x: Double, y: Double)) {
        let d = drag
        let ink = palette.isDark ? UI.brush(239, 239, 236) : UI.brush(20, 20, 24, alpha: 235)
        d.line.background = ink
        d.ring.stroke = ink
        d.outline.borderBrush = palette.isDark ? UI.brush(255, 255, 255, alpha: 90) : UI.brush(0, 0, 0, alpha: 90)
        d.half.stroke = palette.isDark ? UI.brush(255, 255, 255, alpha: 115) : UI.brush(0, 0, 0, alpha: 115)
        d.half.fill = palette.selected
        var line: (x: Double, y: Double, width: Double, height: Double)?
        var ring: (x: Double, y: Double)?
        var outline: Frame?
        var half: Frame?

        switch d.target {
        case .list(let drop)?:
            if let y = drop.lineY, let listFrame = frame(of: list) {
                // Arc: the ring's outer edge 2 DIPs before the favicon (8 into a row, 16 a level),
                // the line's end 3 DIPs inside the row.
                let x = listFrame.x + Double(drop.lineDepth) * 16 + 8 - 2
                ring = (x, y - Self.ringSize / 2)
                line = (x + Self.ringSize - 1, y - Self.lineWidth / 2, listFrame.maxX - 3 - (x + Self.ringSize - 1), Self.lineWidth)
            } else if case .insert(let parent, _)? = drop.target, parent == store.focusedSpace(window: windowID).pinnedContainerID,
                      let divider, let f = frame(of: divider) {
                // An empty pinned section: the line sits on the divider.
                line = (f.x, f.y - Self.lineWidth / 2, f.width, Self.lineWidth)
            }
            if let id = drop.combineRow, let row = rowMeta.first(where: { $0.itemID == id }), let f = frame(of: row.element) {
                outline = f
                if case .split(_, let leading)? = drop.target {
                    half = Frame(x: leading ? f.x + 3 : f.x + f.width / 2, y: f.y + 3, width: f.width / 2 - 3, height: f.height - 6)
                }
            }
        case .favorites(let slot)?:
            if let card = frame(of: favoritesCard) {
                outline = card
            } else {
                let resting = favoriteTiles.filter { $0.id != d.draggedItem }.compactMap { frame(of: $0.element) }
                if slot < resting.count {
                    let f = resting[slot]
                    line = (f.x - Self.tileGap / 2 - Self.lineWidth / 2, f.y, Self.lineWidth, f.height)
                } else if let f = resting.last {
                    line = (f.maxX + Self.tileGap / 2 - Self.lineWidth / 2, f.y, Self.lineWidth, f.height)
                } else if let grid = frame(of: favorites) {
                    outline = grid
                }
            }
        case .space(let id)?:
            outline = spaceCells.first { $0.id == id }.flatMap { frame(of: $0.element) }
        case .spaceCell(let i)?:
            let cells = spaceCells.compactMap { frame(of: $0.element) }
            let from = spaceCells.firstIndex { $0.id == d.draggedSpace } ?? 0
            if cells.indices.contains(i) {
                // The line goes on the side the icon will land: after the cell when moving right.
                let f = cells[i]
                let x = i > from ? f.maxX + 1 : f.x - 1 - Self.lineWidth
                line = (x, f.y + 2, Self.lineWidth, f.height - 4)
            }
        case nil:
            break
        }

        if let line { place(d.line, x: line.x, y: line.y, width: line.width, height: line.height) } else { d.line.visibility = .collapsed }
        if let ring { place(d.ring, x: ring.x, y: ring.y) } else { d.ring.visibility = .collapsed }
        if let o = outline { place(d.outline, x: o.x, y: o.y, width: o.width, height: o.height) } else { d.outline.visibility = .collapsed }
        if let h = half { place(d.half, x: h.x, y: h.y, width: h.width, height: h.height) } else { d.half.visibility = .collapsed }

        // The dragged row, tile or icon fades where it was; its stand-in follows the pointer
        // while the pointer is over the sidebar.
        for row in rowMeta { row.element.opacity = row.itemID == d.draggedItem ? 0.4 : 1 }
        for tile in favoriteTiles { tile.element.opacity = tile.id == d.draggedItem ? 0.4 : 1 }
        for cell in spaceCells { cell.element.opacity = cell.id == d.draggedSpace ? 0.4 : 1 }
        if let bounds = frame(of: root), bounds.contains(p), !d.ghostText.text.isEmpty {
            d.ghost.background = palette.isDark ? UI.brush(46, 46, 46, alpha: 235) : UI.brush(255, 255, 255, alpha: 235)
            d.ghostText.foreground = palette.text
            place(d.ghost, x: p.x + 14, y: p.y + 10)
        } else {
            d.ghost.visibility = .collapsed
        }
    }

    // MARK: Letting go

    private func land(_ source: SidebarDragSource, on target: SidebarDragTarget) {
        switch (source, target) {
        case (.item, .list(let drop)):
            SidebarDropPlan.apply(drop, store: store, window: windowID)
        case (.item(let id), .favorites(let slot)):
            SidebarDropPlan.dropOnFavorites(id, slot: slot, space: store.focusedSpaceID(window: windowID), store: store)
        case (.item(let id), .space(let space)):
            SidebarDropPlan.dropOnSpace(id, space: space, store: store)
        case (.space(let id), .spaceCell(let cell)):
            if let index = SidebarDropPlan.spaceOrderIndex(moving: id, toCell: cell, shown: spaceCells.map(\.id), store: store) {
                store.moveSpace(id, to: index)
            }
        default:
            break
        }
    }
}
