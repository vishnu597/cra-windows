import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WinUI

/// What the Spaces page asks of its window.
@MainActor
protocol SpacesManagerActions: AnyObject {
    /// The tab picked on a card, selected in this window; the Library closes.
    func openFromLibrary(tab id: UUID)
    /// The space in front of this window; the Library closes.
    func openFromLibrary(space id: UUID)
    /// Arc's New Space (the page's +).
    func newSpaceFromLibrary()
    /// Delete Space: Arc asks first.
    func confirmDeleteSpace(_ id: UUID)
}

/// The Library's Spaces page, which Manage Spaces… opens (the Mac's SpacesManagerView, Arc
/// 1.171's spaceManager): every space as a card in its own colours, side by side, scrolling
/// sideways when they don't fit. A card has the space's icon and name, its pinned tabs and
/// folders, Today's tabs, a move handle to drag it along the row and a ⋯ menu; a + after the
/// last card makes a new space. Sizes come from SpacesManagerLayout.
@MainActor
final class SpacesManagerView {
    let root = Grid()
    private let scroll = ScrollViewer()
    private let strip = StackPanel()
    private let store: SidebarStore
    private let windowID: UUID
    private let favicons: Favicons
    private weak var actions: SpacesManagerActions?
    /// The cards on screen, in the page's order, and the transform a drag moves each by.
    private var shown: [UUID] = []
    private var cards: [UUID: Border] = [:]
    private var shifts: [UUID: TranslateTransform] = [:]
    /// The card being dragged by its handle: where the press was, how far it has gone.
    private var dragging: (id: UUID, origin: SpacesManagerLayout.Drag, dx: Double)?
    private var dragHandle: Border?
    private var menuOpen = false
    private var rebuildPending = false
    private var lastDark = false
    private struct CardState: Equatable {
        var space: Space
        var pinned: [UUID]
        var today: [UUID]
        var items: [SidebarItem]
        var expanded: Set<UUID>
    }
    private struct BuildState: Equatable {
        var cards: [CardState]
        var plusTheme: SpaceTheme
        var icons: Int
        var dark: Bool
    }
    private var builtFrom: BuildState?
    /// Controls a handler reaches weakly (winrt-weak-wrappers: a WinRT control made in Swift is
    /// freed once Swift lets go of it).
    private var kept: [AnyObject] = []

    init(store: SidebarStore, windowID: UUID, favicons: Favicons = .shared, actions: SpacesManagerActions) {
        self.store = store
        self.windowID = windowID
        self.favicons = favicons
        self.actions = actions
        strip.orientation = .horizontal
        strip.spacing = SpacesManagerLayout.gap
        strip.padding = Thickness(left: SpacesManagerLayout.lead, top: 0, right: SpacesManagerLayout.trail, bottom: 0)
        scroll.content = strip
        scroll.horizontalScrollBarVisibility = .auto
        scroll.verticalScrollBarVisibility = .disabled
        // It takes the keyboard while the page shows, so Escape reaches the Library, and the
        // arrow keys scroll the cards.
        scroll.isTabStop = true
        root.children.append(scroll)
        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, self.dragging != nil, Int32(truncatingIfNeeded: args.key.rawValue) == 0x1B else { return }
            args.handled = true
            if let id = self.dragging?.id { self.endDrag(id, commit: false) }
        }
    }

    /// The keyboard to the cards' row (the window has moved Win32 focus into the XAML first).
    func focus() {
        _ = try? scroll.focus(.programmatic)
    }

    /// The width the cards need with the Library's rail: LibraryWidth widens the Library to it.
    var cardsWidth: Double {
        SpacesManagerLayout.width(spaces: shownSpaces().count, rail: LibraryLayout.rail)
    }

    private func shownSpaces() -> [UUID] {
        SpacesManagerLayout.spaces(order: store.spaceOrder, standalone: { [store] in store.isStandalone(space: $0) })
    }

    /// Keep the card controls when their contents have not changed: a page's unrelated refresh
    /// must not replace a pointer capture or the button anchoring an open menu.
    func build(dark: Bool) {
        lastDark = dark
        let ids = shownSpaces()
        // Read the inputs even while an interaction holds the controls. BrowserWindow's
        // observation then continues watching these values when a rebuild is deferred.
        let state = BuildState(cards: ids.compactMap(cardState), plusTheme: store.focusedSpace(window: windowID).theme,
                               icons: favicons.revision, dark: dark)
        guard state != builtFrom else { return }
        guard dragging == nil, !menuOpen else { rebuildPending = true; return }
        builtFrom = state
        rebuildPending = false
        strip.children.clear()
        cards = [:]
        shifts = [:]
        kept = []
        shown = ids
        for id in ids {
            guard let space = store.space(id) else { continue }
            let card = makeCard(space)
            cards[id] = card
            strip.children.append(card)
        }
        strip.children.append(makePlus(palette: SidebarPalette(store.focusedSpace(window: windowID).theme)))
    }

    private func cardState(_ id: UUID) -> CardState? {
        guard let space = store.space(id) else { return nil }
        let pinned = store.listedPinnedItems(in: space, window: windowID)
        let today = store.children(of: space.todayContainerID)
        var items: [SidebarItem] = [], expanded: Set<UUID> = [], seen: Set<UUID> = []
        func read(_ item: SidebarItem) {
            guard seen.insert(item.id).inserted else { return }
            items.append(item)
            let open = item.isFolder && store.isExpanded(item.id)
            if open { expanded.insert(item.id) }
            if open || item.isSplit { store.children(of: item.id).forEach(read) }
        }
        (pinned + today).forEach(read)
        return CardState(space: space, pinned: pinned.map(\.id), today: today.map(\.id), items: items, expanded: expanded)
    }

    private func finishInteraction() {
        guard rebuildPending else { return }
        // Leave a menu's Closed/pointer callback before replacing its native anchor.
        _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { [weak self] in
            guard let self else { return }
            self.build(dark: self.lastDark)
        }
    }

    // MARK: Card

    private func makeCard(_ space: Space) -> Border {
        let palette = SidebarPalette(space.theme)
        let id = space.id
        let card = Border()
        card.width = SpacesManagerLayout.card
        card.margin = Thickness(left: 0, top: SpacesManagerLayout.inset, right: 0, bottom: SpacesManagerLayout.inset)
        card.verticalAlignment = .stretch
        card.cornerRadius = CornerRadius(topLeft: 14, topRight: 14, bottomRight: 14, bottomLeft: 14)
        card.background = palette.fill
        let shift = TranslateTransform()
        card.renderTransform = shift
        shifts[id] = shift

        let grid = Grid()
        grid.rowDefinitions.append(UI.row(UI.pixels(SpacesManagerLayout.listTop)))
        grid.rowDefinitions.append(UI.row(UI.star))
        grid.rowDefinitions.append(UI.row(UI.pixels(SpacesManagerLayout.footerHeight)))

        // The header: the space's icon and name, centred 25 DIPs down.
        let header = StackPanel()
        header.orientation = .horizontal
        header.spacing = 8
        header.verticalAlignment = .center
        header.margin = Thickness(left: 16, top: 2 * SpacesManagerLayout.headerCentre - SpacesManagerLayout.listTop, right: 16, bottom: 0)
        let mark = UI.text(space.emoji.isEmpty ? String(space.title.prefix(1)) : space.emoji, size: 14.5, color: palette.text, trimmed: false)
        mark.verticalAlignment = .center
        let title = UI.text(space.title, size: 13, color: palette.secondaryText)
        title.fontWeight = UWP.FontWeight(weight: 600)
        title.verticalAlignment = .center
        header.children.append(mark)
        header.children.append(title)
        grid.children.append(header)

        // The space's pinned rows, a divider, then Today's.
        let rows = StackPanel()
        rows.orientation = .vertical
        rows.spacing = 1
        rows.padding = Thickness(left: 6, top: 3, right: 6, bottom: 6)
        for item in store.listedPinnedItems(in: space, window: windowID) { addRow(item, depth: 0, to: rows, palette: palette) }
        let divider = Border()
        divider.height = 1
        divider.margin = Thickness(left: 10, top: 6, right: 10, bottom: 6)
        divider.background = palette.tile
        rows.children.append(divider)
        let today = store.children(of: space.todayContainerID)
        for item in today { addRow(item, depth: 0, to: rows, palette: palette) }
        if today.isEmpty {
            let none = UI.text("No tabs in Today", size: 12, color: palette.secondaryText)
            none.margin = Thickness(left: 10, top: 2, right: 0, bottom: 0)
            rows.children.append(none)
        }
        let list = ScrollViewer()
        list.content = rows
        list.horizontalScrollBarVisibility = .disabled
        list.verticalScrollBarVisibility = .auto
        grid.children.append(list)
        try? Grid.setRow(list, 1)

        // The footer: the move handle on the left, the ⋯ menu on the right.
        let footer = Grid()
        footer.columnDefinitions.append(UI.column(UI.auto))
        footer.columnDefinitions.append(UI.column(UI.star))
        footer.columnDefinitions.append(UI.column(UI.auto))
        footer.margin = Thickness(left: 9, top: 0, right: 9, bottom: 0)
        let handle = makeMoveHandle(id, palette: palette)
        footer.children.append(handle)
        let moreGlyph = FontIcon()
        moreGlyph.glyph = WinGlyph.code("ellipsis")
        moreGlyph.fontSize = 13
        moreGlyph.foreground = palette.secondaryText
        let more = UI.button(moreGlyph, padding: Thickness(left: 6, top: 6, right: 6, bottom: 6)) {}
        // This button only opens its native flyout; it does not need the sidebar row's
        // press-mode action. Keep the release from bubbling to Library's background tap,
        // which otherwise refocuses the scroll viewer underneath the new menu.
        more.clickMode = .release
        more.tapped.addHandler { _, args in args?.handled = true }
        more.verticalAlignment = .center
        more.flyout = cardMenu(id)
        try? ToolTipService.setToolTip(more, "More")
        try? AutomationProperties.setName(more, "\(space.title) options")
        footer.children.append(more)
        kept.append(more)
        try? Grid.setColumn(more, 2)
        grid.children.append(footer)
        try? Grid.setRow(footer, 2)

        card.child = grid
        card.contextFlyout = cardMenu(id)
        try? AutomationProperties.setName(card, space.title)
        return card
    }

    /// Arc's ⋯ on a card. Move Left and Move Right reorder from the keyboard too.
    private func cardMenu(_ id: UUID) -> MenuFlyout {
        let menu = MenuFlyout()
        menu.opening.addHandler { [weak self] _, _ in self?.menuOpen = true }
        menu.closed.addHandler { [weak self] _, _ in
            self?.menuOpen = false
            self?.finishInteraction()
        }
        kept.append(menu)
        menu.items.append(UI.menuItem("Open Space") { [weak self] in self?.actions?.openFromLibrary(space: id) })
        menu.items.append(MenuFlyoutSeparator())
        let left = UI.menuItem("Move Left") { [weak self] in self?.move(id, by: -1) }
        let right = UI.menuItem("Move Right") { [weak self] in self?.move(id, by: 1) }
        left.isEnabled = shown.first != id
        right.isEnabled = shown.last != id
        menu.items.append(left)
        menu.items.append(right)
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Clear Today") { [weak self] in self?.store.clearToday(id, playing: []) })
        if store.spaceOrder.count > 1 {
            menu.items.append(MenuFlyoutSeparator())
            menu.items.append(UI.menuItem("Delete Space…") { [weak self] in self?.actions?.confirmDeleteSpace(id) })
        }
        return menu
    }

    private func move(_ id: UUID, by steps: Int) {
        guard let to = SpacesManagerLayout.move(id, by: steps, shown: shown, spaceOrder: store.spaceOrder) else { return }
        store.moveSpace(id, to: to)
    }

    // MARK: Rows

    private func addRow(_ item: SidebarItem, depth: Int, to rows: StackPanel, palette: SidebarPalette) {
        if item.isFolder {
            let open = store.isExpanded(item.id)
            let id = item.id
            rows.children.append(row(glyph: open ? "▾" : "▸", key: nil, title: item.displayTitle, depth: depth, palette: palette) { [weak self] in
                self?.store.setExpanded(id, !open)
            })
            if open { for child in store.children(of: item.id) { addRow(child, depth: depth + 1, to: rows, palette: palette) } }
        } else if item.isSplit {
            let titles = store.children(of: item.id).map(\.displayTitle).joined(separator: " | ")
            let first = store.paneTabIDs(for: item.children.first ?? item.id).first
            rows.children.append(row(glyph: "⧉", key: nil, title: titles, depth: depth, palette: palette) { [weak self] in
                if let first { self?.actions?.openFromLibrary(tab: first) }
            })
        } else if item.isTab {
            let id = item.id
            rows.children.append(row(glyph: nil, key: item.tab?.iconKey, title: item.displayTitle, depth: depth, palette: palette) { [weak self] in
                self?.actions?.openFromLibrary(tab: id)
            })
        }
    }

    /// A 32 DIP row: the favicon (or a folder's or split's mark), then the title.
    private func row(glyph: String?, key: String?, title: String, depth: Int, palette: SidebarPalette,
                     _ action: @escaping @MainActor () -> Void) -> Button {
        let content = Grid()
        content.columnDefinitions.append(UI.column(UI.pixels(16)))
        content.columnDefinitions.append(UI.column(UI.star))
        content.columnSpacing = 10
        let icon: FrameworkElement
        if let glyph {
            icon = UI.text(glyph, color: palette.secondaryText, trimmed: false)
        } else if let bitmap = favicons.bitmap(forKey: key, onDark: palette.isDark) {
            icon = UI.image(bitmap, size: 16)
        } else {
            let globe = FontIcon()
            globe.glyph = WinGlyph.code("globe")
            globe.fontSize = 13
            globe.foreground = palette.secondaryText
            icon = globe
        }
        icon.verticalAlignment = .center
        content.children.append(icon)
        let label = UI.text(title.isEmpty ? "Untitled" : title, size: 13, color: palette.text)
        label.verticalAlignment = .center
        content.children.append(label)
        try? Grid.setColumn(label, 1)
        let button = UI.button(content, padding: Thickness(left: 8 + Double(depth) * 14, top: 0, right: 8, bottom: 0), action)
        button.height = 32
        button.horizontalAlignment = .stretch
        button.horizontalContentAlignment = .stretch
        button.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        try? AutomationProperties.setName(button, title)
        return button
    }

    // MARK: Moving a card

    /// Arc's four-way arrow: dragging it carries the card along the row; where its centre is let
    /// go is the space's new place (SpacesManagerLayout.drop).
    private func makeMoveHandle(_ id: UUID, palette: SidebarPalette) -> Border {
        let glyph = FontIcon()
        glyph.glyph = "\u{E7C2}"  // Move
        glyph.fontSize = 13
        glyph.foreground = palette.secondaryText
        let handle = Border()
        handle.child = glyph
        handle.width = 26
        handle.height = 26
        handle.verticalAlignment = .center
        handle.background = UI.clear  // takes the press over its whole square
        try? ToolTipService.setToolTip(handle, "Drag to Move")
        try? AutomationProperties.setName(handle, "Move Space")
        // Weakly: `kept` holds the handle while it is on screen, and a strong capture in its own
        // handler would keep it forever.
        handle.pointerPressed.addHandler { [weak self, weak handle] _, args in
            guard let self, let handle, let args, self.dragging == nil, let index = self.shown.firstIndex(of: id),
                  let point = try? args.getCurrentPoint(self.root),
                  args.pointer?.pointerDeviceType != .mouse || point.properties?.isLeftButtonPressed == true,
                  (try? handle.capturePointer(args.pointer)) == true else { return }
            args.handled = true
            self.dragging = (id, SpacesManagerLayout.Drag(pointerX: Double(point.position.x), scrollOffset: self.scroll.horizontalOffset,
                                                         index: index, count: self.shown.count), 0)
            self.dragHandle = handle
            if let card = self.cards[id] { try? Canvas.setZIndex(card, 1) }
        }
        handle.pointerMoved.addHandler { [weak self] _, args in
            guard let self, let args, let drag = self.dragging, drag.id == id,
                  let point = try? args.getCurrentPoint(self.root) else { return }
            args.handled = true
            self.moveDrag(id, pointerX: Double(point.position.x))
        }
        handle.pointerReleased.addHandler { [weak self] _, args in
            guard let self else { return }
            args?.handled = true
            if let args, let point = try? args.getCurrentPoint(self.root) {
                self.moveDrag(id, pointerX: Double(point.position.x))
            }
            self.endDrag(id, commit: true)
        }
        handle.pointerCaptureLost.addHandler { [weak self] _, _ in self?.endDrag(id, commit: false) }
        handle.pointerCanceled.addHandler { [weak self] _, _ in self?.endDrag(id, commit: false) }
        kept.append(handle)
        return handle
    }

    private func moveDrag(_ id: UUID, pointerX: Double) {
        guard let drag = dragging, drag.id == id else { return }
        let dx = drag.origin.offset(pointerX: pointerX, scrollOffset: scroll.horizontalOffset)
        dragging = (id, drag.origin, dx)
        shifts[id]?.x = dx
    }

    private func endDrag(_ id: UUID, commit: Bool) {
        guard let drag = dragging, drag.id == id else { return }
        dragging = nil
        let handle = dragHandle
        dragHandle = nil
        _ = try? handle?.releasePointerCaptures()
        shifts[id]?.x = 0
        if let card = cards[id] { try? Canvas.setZIndex(card, 0) }
        // The store's change draws the cards again in their new order.
        if commit, let to = SpacesManagerLayout.drop(id, dx: drag.dx, shown: shown, spaceOrder: store.spaceOrder) {
            store.moveSpace(id, to: to)
        }
        finishInteraction()
    }

    // MARK: New Space

    /// The + after the last card, in the window's space colours (Arc 1.172.1: a cream disc with a
    /// dark + in an olive space).
    private func makePlus(palette: SidebarPalette) -> Button {
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code("plus")
        glyph.fontSize = 12
        glyph.foreground = palette.fill
        let plus = UI.button(glyph, fill: palette.text, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
            self?.actions?.newSpaceFromLibrary()
        }
        plus.width = SpacesManagerLayout.plus
        plus.height = SpacesManagerLayout.plus
        let r = SpacesManagerLayout.plus / 2
        plus.cornerRadius = CornerRadius(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
        plus.verticalAlignment = .center
        plus.margin = Thickness(left: SpacesManagerLayout.plusGap - SpacesManagerLayout.gap, top: 0, right: 0, bottom: 0)
        try? ToolTipService.setToolTip(plus, "New Space")
        try? AutomationProperties.setName(plus, "New Space")
        return plus
    }
}
