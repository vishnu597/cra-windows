import CraCore
import Foundation
import UWP
import WinSDK
import WinUI

/// One space in the dock (the Mac's SpaceCellView): its emoji, symbol or picture, faint unless
/// lit, or Arc's dot for a space with no icon and, in a squeezed dock, for every space but the
/// one in the wide cell. A Button, so a press starts the dock's drag (SidebarDrag) and the click
/// switches spaces; its own hover fill is replaced by Arc's.
@MainActor
final class SidebarDockCell {
    let id: UUID
    let icon: SpaceIcon
    let button: Button
    private let fill = Border()
    private let emoji = TextBlock()
    private let glyph = FontIcon()
    private let picture = WinUI.Image()
    private let dot = WinUI.Ellipse()  // not GDI's Ellipse
    private var pictureData: Data?

    init(id: UUID, icon: SpaceIcon, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.icon = icon
        let content = Grid()
        fill.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        emoji.fontSize = 14
        emoji.horizontalAlignment = .center
        emoji.verticalAlignment = .center
        emoji.textAlignment = .center
        glyph.fontSize = 12
        glyph.horizontalAlignment = .center
        glyph.verticalAlignment = .center
        picture.width = 16
        picture.height = 16
        picture.stretch = .uniform
        picture.horizontalAlignment = .center
        picture.verticalAlignment = .center
        dot.horizontalAlignment = .center
        dot.verticalAlignment = .center
        for part: UIElement in [fill, emoji, glyph, picture, dot] { content.children.append(part) }
        button = UI.button(content, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0), action)
        button.height = SidebarView.dockCellHeight
        // Arc's cell has its own fill rules (no fill when squeezed), so WinUI's goes.
        for key in ["ButtonBackgroundPointerOver", "ButtonBackgroundPressed"] { _ = button.resources.insert(key, UI.clear) }
        content.horizontalAlignment = .stretch
        content.verticalAlignment = .stretch
        button.horizontalContentAlignment = .stretch
        button.verticalContentAlignment = .stretch
    }

    /// Draws `mark` in a cell `width` DIPs wide. `lit`: full ink (SpaceDock.isLit); `filled`:
    /// Arc's hovered or pressed fill, which a squeezed dock never shows.
    func apply(width: Double, mark: SpaceDockMark, lit: Bool, filled: Bool, palette: SidebarPalette) {
        button.width = width
        let dark = palette.isDark
        fill.background = filled ? (dark ? UI.brush(255, 255, 255, alpha: 20) : UI.brush(0, 0, 0, alpha: 13)) : UI.clear
        emoji.visibility = .collapsed
        glyph.visibility = .collapsed
        picture.visibility = .collapsed
        dot.visibility = .collapsed
        let faint = lit ? 1.0 : 0.45
        switch mark {
        case .emoji(let e):
            emoji.text = e
            emoji.opacity = faint
            emoji.visibility = .visible
        case .symbol(let name):
            glyph.glyph = WinGlyph.known(name) ?? WinGlyph.code("space")
            glyph.foreground = palette.text
            glyph.opacity = faint
            glyph.visibility = .visible
        case .image(let data):
            if pictureData != data {
                pictureData = data
                picture.source = Pixels.decode(data, side: 32)?.bitmap()
            }
            picture.opacity = faint
            picture.visibility = .visible
        case .dot(let diameter):
            dot.width = Double(diameter)
            dot.height = Double(diameter)
            let alpha = UInt8((SpaceDock.dotAlpha(dark: dark, lit: lit) * 255).rounded())
            dot.fill = dark ? UI.brush(255, 255, 255, alpha: alpha) : UI.brush(0, 0, 0, alpha: alpha)
            dot.visibility = .visible
        }
    }
}

// MARK: The dock

extension SidebarView {
    static let dockCellHeight = 32.0

    /// The space icons between the Library and + buttons (the Mac's SpaceDockView): every space
    /// an even share of the room up to 34 DIPs, squeezed into dots below 22 with the open space,
    /// or the hovered one, in the wide cell (CraCore's SpaceDock).
    func buildSpacesBar(_ focused: Space) {
        spacesBar.children.clear()
        spaceCells = []
        dockCells = []
        // An incognito window pages only its own space (SidebarStore.pagedSpaces).
        for space in store.pagedSpaces(window: windowID) where !store.hidesSpaceHeader(space.id) {
            let id = space.id
            let cell = SidebarDockCell(id: id, icon: space.icon) { [weak self] in
                self?.dragPressed(.space(id))
                self?.store.focusSpace(id, window: self?.windowID)
            }
            cell.button.pointerEntered.addHandler { [weak self] _, _ in self?.hoverDock(id) }
            cell.button.pointerExited.addHandler { [weak self] _, _ in
                if self?.dockHovered == id { self?.hoverDock(nil) }
            }
            try? ToolTipService.setToolTip(cell.button, dockTip(space))
            try? AutomationProperties.setName(cell.button, space.title)
            cell.button.contextFlyout = spaceMenu(space)
            dockCells.append(cell)
            spaceCells.append((cell.button, id))
            spacesBar.children.append(cell.button)
        }
        if dockHovered.map({ id in !dockCells.contains { $0.id == id } }) ?? false { dockHovered = nil }
        plusButton.visibility = store.isIncognito(space: focused.id) ? .collapsed : .visible
        plusButton.foreground = palette.secondaryText
        refreshDock()
    }

    /// The pointer came onto a space's cell (nil: off the dock). A squeezed dock hands the wide
    /// cell to it (#252).
    func hoverDock(_ id: UUID?) {
        guard dockHovered != id else { return }
        dockHovered = id
        refreshDock()
    }

    /// Widths and marks from SpaceDock for the cells as drawn. Arc slides the cells over 0.2 s;
    /// here they change at once.
    func refreshDock() {
        let ids = dockCells.map(\.id)
        let focused = store.focusedSpaceID(window: windowID)
        // While a space is dragged the open space keeps the wide cell, as on the Mac.
        let hovered = drag.dragging ? nil : dockHovered
        let room = SpaceDock.room(dockWidth: CGFloat(dockWidth))
        let squeezed = SpaceDock.isSqueezed(count: ids.count, room: room)
        let wide = SpaceDock.wide(open: focused, hovered: hovered)
        let widths = SpaceDock.widths(count: ids.count, open: wide.flatMap { ids.firstIndex(of: $0) }, room: room)
        for (i, cell) in dockCells.enumerated() {
            let isOpen = cell.id == focused, isHovered = cell.id == hovered, isWide = cell.id == wide
            let lit = SpaceDock.isLit(isOpen: isOpen, hovered: isHovered, pressed: false, isWide: isWide, squeezed: squeezed)
            cell.apply(width: Double(widths[i]), mark: SpaceDock.mark(for: cell.icon, isOpen: isWide, squeezed: squeezed),
                       lit: lit, filled: isHovered && !squeezed, palette: palette)
        }
    }

    /// The dock's width: the sidebar's footer once laid out, else the window's sidebar less its
    /// margins.
    var dockWidth: Double {
        let w = footer.actualWidth
        return w > 0 ? w : 260
    }

    /// Arc's tip: the space's name, its profile in a pill, then Go to Space N's keys.
    private func dockTip(_ space: Space) -> FrameworkElement {
        let tip = SpaceDock.tip(title: space.title, profileName: store.profile(space.profileID)?.name,
                                index: store.spaceOrder.firstIndex(of: space.id))
        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 6
        let name = TextBlock()
        name.text = tip.title.isEmpty ? "Space" : tip.title
        name.verticalAlignment = .center
        row.children.append(name)
        let pill = Border()
        pill.cornerRadius = CornerRadius(topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
        pill.padding = Thickness(left: 5, top: 1, right: 5, bottom: 1)
        pill.background = UI.brush(128, 128, 128, alpha: 60)
        pill.verticalAlignment = .center
        let profile = TextBlock()
        profile.text = tip.profile
        profile.fontSize = 11
        pill.child = profile
        row.children.append(pill)
        if let n = tip.number, let chord = WinKeyBindings.shared.action("space\(n)")?.primary {
            let keys = TextBlock()
            keys.text = chord.windowsDisplay
            keys.opacity = 0.6
            keys.verticalAlignment = .center
            row.children.append(keys)
        }
        return row
    }

    /// Shift + wheel or a sideways wheel over the sidebar: the next or previous space, as in Arc
    /// (WheelSpaceSwitch, #93). The Library isn't paged to from here.
    func wheelOverSidebar(delta: Int, horizontal: Bool) -> Bool {
        let shift = GetKeyState(0x10) < 0
        guard horizontal || shift else { return false }
        let dx = WheelSpaceSwitch.lines(windowsDelta: delta, horizontal: horizontal)
        let step = wheel.step(dx: dx, inverted: false, at: Double(GetTickCount64()) / 1000)
        let paged = store.pagedSpaces(window: windowID).filter { !store.hidesSpaceHeader($0.id) }
        guard step != 0, let index = paged.firstIndex(where: { $0.id == store.focusedSpaceID(window: windowID) }),
              case .space(let next)? = WheelSpaceSwitch.target(step: step, index: index, count: paged.count,
                                                               inLibrary: false, libraryAllowed: false)
        else { return true }
        store.focusSpace(paged[next].id, window: windowID)
        return true
    }
}
