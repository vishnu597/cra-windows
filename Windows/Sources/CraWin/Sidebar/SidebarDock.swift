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
    /// The dock's cell for the space Create a Space is making, after the last space.
    static let pendingSpaceID = UUID()

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
            let tip = dockTip(space)
            ArcTip.set(cell.button, tip.help, placement: .above, badge: tip.profile)
            try? AutomationProperties.setName(cell.button, space.title)
            cell.button.contextFlyout = spaceMenu(space)
            dockCells.append(cell)
            spaceCells.append((cell.button, id))
            spacesBar.children.append(cell.button)
        }
        // The space being made: Arc's lit dot after the last space, its icon once a theme is
        // chosen (SpaceCreationDraft.dockMark). A click takes the keys back to its name.
        if creationPage != nil {
            let cell = SidebarDockCell(id: Self.pendingSpaceID, icon: .none) { [weak self] in self?.creationPage?.focusName() }
            try? AutomationProperties.setName(cell.button, "New space")
            dockCells.append(cell)
            spacesBar.children.append(cell.button)
        }
        if dockHovered.map({ id in !dockCells.contains { $0.id == id } }) ?? false { dockHovered = nil }
        // Right-clicking the dock past its icons is Windows' Spaces menu (the Mac's menu bar has one).
        footer.contextFlyout = store.isIncognito(space: focused.id) ? nil : spacesMenu(focused)
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
        // While a space is being made its pending cell is the open one.
        let pending = creationPage?.draft
        let focused = pending == nil ? store.focusedSpaceID(window: windowID) : Self.pendingSpaceID
        // While a space is dragged the open space keeps the wide cell, as on the Mac.
        let hovered = drag.dragging ? nil : dockHovered
        let room = SpaceDock.room(dockWidth: CGFloat(dockWidth))
        let squeezed = SpaceDock.isSqueezed(count: ids.count, room: room)
        let wide = SpaceDock.wide(open: focused, hovered: hovered)
        let widths = SpaceDock.widths(count: ids.count, open: wide.flatMap { ids.firstIndex(of: $0) }, room: room)
        for (i, cell) in dockCells.enumerated() {
            let isOpen = cell.id == focused, isHovered = cell.id == hovered, isWide = cell.id == wide
            let lit = SpaceDock.isLit(isOpen: isOpen, hovered: isHovered, pressed: false, isWide: isWide, squeezed: squeezed)
            let mark = cell.id == Self.pendingSpaceID ? (pending?.dockMark ?? .dot(diameter: SpaceDock.dotDiameter))
                : SpaceDock.mark(for: cell.icon, isOpen: isWide, squeezed: squeezed)
            cell.apply(width: Double(widths[i]), mark: mark, lit: lit, filled: isHovered && !squeezed, palette: palette)
        }
    }

    /// The dock's width: the sidebar's footer once laid out, else the window's sidebar less its
    /// margins.
    var dockWidth: Double {
        let w = footer.actualWidth
        return w > 0 ? w : 260
    }

    /// Arc's tip (ArcTip, as the Mac's SpaceDockIconView): the space's name, its profile in a pill,
    /// then Go to Space N's keys in caps, above the icon 0.55 s after the pointer rests.
    private func dockTip(_ space: Space) -> (help: String, profile: String) {
        let tip = SpaceDock.tip(title: space.title, profileName: store.profile(space.profileID)?.name,
                                index: store.spaceOrder.firstIndex(of: space.id))
        let name = tip.title.isEmpty ? "Space" : tip.title
        guard let n = tip.number, let chord = WinKeyBindings.shared.action("space\(n)")?.primary else { return (name, tip.profile) }
        return ("\(name) (\(chord.windowsDisplay))", tip.profile)
    }

    /// Shift + wheel or a sideways wheel over the sidebar: the next or previous space, as in Arc
    /// (WheelSpaceSwitch, #93). The Library isn't paged to from here.
    func wheelOverSidebar(delta: Int, horizontal: Bool) -> Bool {
        let shift = GetKeyState(0x10) < 0
        guard horizontal || shift else { return false }
        let dx = WheelSpaceSwitch.lines(windowsDelta: delta, horizontal: horizontal)
        let paged = store.pagedSpaces(window: windowID).filter { !store.hidesSpaceHeader($0.id) }
        // A touchpad's sideways swipe on the last space pulls Arc's "+" out instead (#564).
        let onLast = paged.last?.id == store.focusedSpaceID(window: windowID)
        if horizontal, pullNewSpace(lines: dx, onLastSpace: onLast) { return true }
        let step = wheel.step(dx: dx, inverted: false, at: Double(GetTickCount64()) / 1000)
        guard step != 0, let index = paged.firstIndex(where: { $0.id == store.focusedSpaceID(window: windowID) }),
              case .space(let next)? = WheelSpaceSwitch.target(step: step, index: index, count: paged.count,
                                                               inLibrary: false, libraryAllowed: false)
        else { return true }
        store.focusSpace(paged[next].id, window: windowID)
        return true
    }

    /// Arc's + creation menu (SidebarCreationEntries): New Space, New Folder, New Split and New
    /// Tab with their keys; Easels and Boosts aren't on Windows yet, so their rows are left out.
    func showCreationMenu() {
        let selected = store.selectedTabID(window: windowID)
        let entries = SidebarCreationEntries.entries(selectedURL: selected.flatMap { store.item($0)?.tab?.url },
                                                     selectedPanes: selected.map { store.paneTabIDs(for: $0).count },
                                                     paneLimit: store.splitPaneLimit)
        let menu = MenuFlyout()
        for entry in entries {
            guard let binding = WinKeyBindings.shared.action(entry.action) else { continue }
            let action = entry.action
            let item = UI.menuItem(entry.title) { [weak self] in self?.actions?.runCommand(action) }
            if let glyph = WinGlyph.known(entry.symbol) {
                let icon = FontIcon()
                icon.glyph = glyph
                item.icon = icon
            }
            if let chord = binding.primary { item.keyboardAcceleratorTextOverride = chord.windowsDisplay }
            item.isEnabled = entry.enabled
            menu.items.append(item)
        }
        creationMenu = menu
        try? menu.showAt(plusButton)
    }

    /// The Mac's Spaces menu (SpacesMenu, in its menu bar), which Windows shows from the dock: its
    /// commands with their keys, every space by name and icon with Go to Space N's keys for the
    /// first nine and the open one checked, then Manage Spaces… (SpacesMenuComposition).
    func spacesMenu(_ focused: Space) -> MenuFlyout {
        let menu = MenuFlyout()
        menu.shouldConstrainToRootBounds = false
        func command(_ id: String) {
            guard let action = WinKeyBindings.shared.action(id) else { return }
            menu.items.append(UI.menuItem(action.name, action: id) { [weak self] in self?.actions?.runCommand(id) })
        }
        for group in SpacesMenuComposition.commandsBefore {
            group.forEach(command)
            menu.items.append(MenuFlyoutSeparator())
        }
        let spaces = store.orderedSpaces
        for (row, space) in zip(SpacesMenuComposition(spaceIDs: spaces.map(\.id)).navigation, spaces) {
            let item = ToggleMenuFlyoutItem()
            let name = SpacesMenuComposition.displayedName(space.title)
            let emoji = space.icon.emoji
            item.text = emoji.isEmpty ? name : "\(emoji)  \(name)"
            if name != space.title { try? ToolTipService.setToolTip(item, space.title) }
            if let symbol = space.icon.symbol, let glyph = WinGlyph.known(symbol) {
                let icon = FontIcon()
                icon.glyph = glyph
                item.icon = icon
            }
            item.isChecked = row.spaceID == focused.id
            if let id = row.shortcutID, let keys = WinKeyBindings.shared.action(id)?.primary?.windowsDisplay {
                item.keyboardAcceleratorTextOverride = keys
            }
            let spaceID = row.spaceID
            item.click.addHandler { [weak self] _, _ in
                guard let self, self.store.space(spaceID) != nil else { return }
                self.store.focusSpace(spaceID, window: self.windowID)
            }
            menu.items.append(item)
        }
        menu.items.append(MenuFlyoutSeparator())
        SpacesMenuComposition.commandsAfter.forEach(command)
        return menu
    }
}
