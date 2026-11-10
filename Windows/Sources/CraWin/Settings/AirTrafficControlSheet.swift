import CraCore
import Foundation
import UWP
import WinUI

/// Arc's Air Traffic Control sheet (AirTrafficControlView on the Mac), over the Settings window:
/// the title and New Route over a hairline, one two-line route per entry ("🔗 URL [Contains ⌄]
/// [text] ⊖" / "↳ Open in [Space ⌄]"), then Default below a second hairline, on a 508×440 DIP
/// card. Escape, the ✕ or a click beside the card closes it. Routes are saved as they are edited.
@MainActor
final class AirTrafficControlSheet {
    /// Covers the whole window, dimming it; collapsed while the sheet is closed.
    let root = Grid()
    private let store: SidebarStore
    private let palette: SettingsPalette
    private let card = Border()
    private let routes = StackPanel()
    private let emptyNote: TextBlock
    private let scroll = ScrollViewer()
    private let defaultRow = StackPanel()
    private var newRoute: Button!
    /// The rows' controls, which their handlers capture weakly: a WinRT control made from Swift is
    /// only a wrapper, gone once nothing in Swift holds it (see SettingsPanes.profiles).
    private var kept: [AnyObject] = []
    /// Each route's URL field, so New Route can hand the new one the keyboard.
    private var fields: [UUID: TextBox] = [:]

    var isShown: Bool { root.visibility == .visible }

    init(store: SidebarStore, palette: SettingsPalette) {
        self.store = store
        self.palette = palette
        emptyNote = UI.text(AirTrafficControl.emptyNote, size: 12, color: palette.secondaryText, trimmed: false)
        root.visibility = .collapsed
        root.background = UI.brush(0, 0, 0, alpha: palette.isDark ? 110 : 60)
        // A click beside the card closes it, as Escape does (the window behind is dimmed and
        // can't be used while the sheet is up).
        root.tapped.addHandler { [weak self] _, args in
            guard let self, let args, !args.handled else { return }
            self.hide()
        }

        card.width = 508
        card.height = 440
        card.horizontalAlignment = .center
        card.verticalAlignment = .center
        card.cornerRadius = CornerRadius(topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10)
        card.background = palette.window
        card.borderBrush = palette.hairline
        card.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        card.padding = Thickness(left: 24, top: 0, right: 24, bottom: 0)
        // Tab stays on the card while it is up, not on the pane behind it.
        card.tabFocusNavigation = .cycle
        card.tapped.addHandler { _, args in
            args?.handled = true
        }
        root.children.append(card)

        let layout = Grid()
        layout.rowDefinitions.append(UI.row(UI.pixels(84)))
        layout.rowDefinitions.append(UI.row(UI.pixels(1)))
        layout.rowDefinitions.append(UI.row(UI.star))
        layout.rowDefinitions.append(UI.row(UI.pixels(1)))
        layout.rowDefinitions.append(UI.row(UI.pixels(90)))
        card.child = layout

        let header = makeHeader()
        layout.children.append(header)
        for row in [Int32(1), 3] {
            let line = Border()
            line.background = palette.hairline
            layout.children.append(line)
            try? Grid.setRow(line, row)
        }

        let middle = Grid()
        routes.orientation = .vertical
        routes.spacing = 24
        routes.padding = Thickness(left: 31, top: 24, right: 0, bottom: 16)
        scroll.content = routes
        scroll.horizontalScrollBarVisibility = .disabled
        scroll.verticalScrollBarVisibility = .auto
        middle.children.append(scroll)
        emptyNote.textWrapping = .wrap
        emptyNote.textAlignment = .center
        emptyNote.maxWidth = 300
        emptyNote.horizontalAlignment = .center
        emptyNote.verticalAlignment = .center
        middle.children.append(emptyNote)
        layout.children.append(middle)
        try? Grid.setRow(middle, 2)

        defaultRow.orientation = .horizontal
        defaultRow.verticalAlignment = .center
        defaultRow.padding = Thickness(left: 36, top: 0, right: 0, bottom: 0)
        layout.children.append(defaultRow)
        try? Grid.setRow(defaultRow, 4)
    }

    /// The button that opened the sheet, which has the keyboard again once it closes.
    private weak var opener: Button?

    /// Arc opens the sheet with nothing chosen; the keyboard starts on New Route.
    func show(from opener: Button?) {
        self.opener = opener
        rebuild()
        root.visibility = .visible
        _ = try? newRoute.focus(.programmatic)
    }

    func hide() {
        guard isShown else { return }
        root.visibility = .collapsed
        routes.children.clear()
        defaultRow.children.clear()
        kept.removeAll()
        fields.removeAll()
        _ = try? opener?.focus(.programmatic)
    }

    // MARK: Layout

    private func makeHeader() -> Grid {
        let header = Grid()
        header.padding = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        header.columnDefinitions.append(UI.column(UI.star))
        header.columnDefinitions.append(UI.column(UI.auto))
        header.columnDefinitions.append(UI.column(UI.auto))
        let title = UI.text(AirTrafficControl.title, color: palette.text)
        title.fontWeight = UWP.FontWeight(weight: 700)
        title.verticalAlignment = .center
        header.children.append(title)

        let add = Button()
        add.content = UI.text("New Route", trimmed: false)
        add.width = 94
        add.horizontalContentAlignment = .center
        add.verticalAlignment = .center
        add.click.addHandler { [weak self] _, _ in self?.addRoute() }
        newRoute = add
        header.children.append(add)
        try? Grid.setColumn(add, 1)

        let glyph = FontIcon()
        glyph.glyph = "\u{E711}"  // Cancel
        glyph.fontSize = 13
        glyph.foreground = palette.secondaryText
        let close = UI.button(glyph, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in self?.hide() }
        close.width = 32
        close.height = 32
        close.margin = Thickness(left: 24, top: 0, right: 0, bottom: 0)
        close.verticalAlignment = .center
        try? ToolTipService.setToolTip(close, "Close")
        try? AutomationProperties.setName(close, "Close")
        header.children.append(close)
        try? Grid.setColumn(close, 2)
        return header
    }

    /// The routes and the Default row, from the settings as they are now.
    private func rebuild() {
        routes.children.clear()
        defaultRow.children.clear()
        kept.removeAll()
        fields.removeAll()
        for route in store.settings.linkRoutes { routes.children.append(routeRow(route)) }
        emptyNote.visibility = store.settings.linkRoutes.isEmpty ? .visible : .collapsed

        let label = UI.text("Default", color: palette.text)
        label.width = 104
        label.verticalAlignment = .center
        defaultRow.children.append(label)
        defaultRow.children.append(destinationButton(store.settings.defaultLinkDestination, name: "Default destination") { [store] destination in
            store.settings.defaultLinkDestination = destination
        })
    }

    private func routeRow(_ route: LinkRoute) -> UIElement {
        let id = route.id
        let row = StackPanel()
        row.orientation = .vertical
        row.spacing = 4

        let first = StackPanel()
        first.orientation = .horizontal
        first.spacing = 8
        let url = label("URL", glyph: "\u{E71B}")  // Link
        url.width = 49
        first.children.append(url)

        let styles = LinkMatchStyle.allCases
        let match = ComboBox()
        match.width = 110
        match.verticalAlignment = .center
        for style in styles { match.items.append(style.label) }
        match.selectedIndex = Int32(styles.firstIndex(of: route.match) ?? 0)
        match.selectionChanged.addHandler { [weak self, weak match] _, _ in
            guard let match, styles.indices.contains(Int(match.selectedIndex)) else { return }
            self?.update(id) { $0.match = styles[Int(match.selectedIndex)] }
        }
        try? AutomationProperties.setName(match, "Match")
        first.children.append(match)

        let field = TextBox()
        field.width = 210
        field.verticalAlignment = .center
        field.text = route.text
        field.placeholderText = AirTrafficControl.placeholder
        field.textChanged.addHandler { [weak self, weak field] _, _ in
            guard let field else { return }
            let text = field.text
            self?.update(id) { $0.text = text }
        }
        try? AutomationProperties.setName(field, "Link URL")
        first.children.append(field)

        let minus = FontIcon()
        minus.glyph = "\u{ECC9}"  // RemoveFrom: a minus in a circle
        minus.fontSize = 14
        minus.foreground = palette.secondaryText
        let remove = UI.button(minus, padding: Thickness(left: 4, top: 4, right: 4, bottom: 4)) { [weak self] in self?.removeRoute(id) }
        remove.verticalAlignment = .center
        try? AutomationProperties.setName(remove, "Remove")
        try? ToolTipService.setToolTip(remove, "Remove")
        first.children.append(remove)
        row.children.append(first)

        let second = StackPanel()
        second.orientation = .horizontal
        second.spacing = 8
        second.padding = Thickness(left: 74, top: 0, right: 0, bottom: 0)
        let openIn = label("Open in", glyph: "\u{E7A6}")  // Redo: an arrow turning right
        openIn.width = 70
        second.children.append(openIn)
        second.children.append(destinationButton(route.destination, name: "Open in") { [weak self] destination in
            self?.update(id) { $0.destination = destination }
        })
        row.children.append(second)
        kept += [match, field]
        fields[id] = field
        return row
    }

    /// Arc's destination menu: "Open in Space" over Most Recent Space and every space, then
    /// Little Window after a separator, the current one checked.
    private func destinationButton(_ current: LinkDestination, name: String,
                                   _ choose: @escaping @MainActor (LinkDestination) -> Void) -> Button {
        let spaces = store.orderedSpaces
        let choices = AirTrafficControl.choices(spaces: spaces)
        let shown = AirTrafficControl.shown(current, spaces: spaces)

        let title = UI.text(choices.first { $0.destination == shown }?.title ?? "", color: palette.text)
        title.verticalAlignment = .center
        let chevron = FontIcon()
        chevron.glyph = "\u{E70D}"  // ChevronDown
        chevron.fontSize = 10
        chevron.foreground = palette.secondaryText
        chevron.verticalAlignment = .center
        let content = Grid()
        content.columnDefinitions.append(UI.column(UI.star))
        content.columnDefinitions.append(UI.column(UI.auto))
        content.children.append(title)
        content.children.append(chevron)
        try? Grid.setColumn(chevron, 1)

        let button = Button()
        button.content = content
        button.width = 165
        button.horizontalContentAlignment = .stretch
        button.verticalAlignment = .center
        try? AutomationProperties.setName(button, name)

        let menu = MenuFlyout()
        let checks = MenuChecks()
        let heading = MenuFlyoutItem()
        heading.text = "Open in Space"
        heading.isEnabled = false
        menu.items.append(heading)
        for choice in choices {
            if choice.afterSeparator { menu.items.append(MenuFlyoutSeparator()) }
            let item = ToggleMenuFlyoutItem()
            item.text = choice.title
            item.isChecked = choice.destination == shown
            let destination = choice.destination
            item.click.addHandler { [weak title, weak checks] _, _ in
                title?.text = choice.title
                choose(destination)
                // The checks follow the choice for the next time the menu opens.
                checks?.check(destination)
            }
            checks.items.append((destination, item))
            menu.items.append(item)
        }
        button.flyout = menu
        kept += [title, menu, checks]
        return button
    }

    /// Secondary 13 DIP text with its glyph in front ("🔗 URL", "↳ Open in").
    private func label(_ text: String, glyph: String) -> StackPanel {
        let panel = StackPanel()
        panel.orientation = .horizontal
        panel.spacing = 6
        panel.verticalAlignment = .center
        let icon = FontIcon()
        icon.glyph = glyph
        icon.fontSize = 12
        icon.foreground = palette.secondaryText
        icon.verticalAlignment = .center
        panel.children.append(icon)
        let t = UI.text(text, color: palette.secondaryText, trimmed: false)
        t.verticalAlignment = .center
        panel.children.append(t)
        return panel
    }

    // MARK: Editing

    private func update(_ id: UUID, _ change: (inout LinkRoute) -> Void) {
        guard let i = store.settings.linkRoutes.firstIndex(where: { $0.id == id }) else { return }
        var route = store.settings.linkRoutes[i]
        change(&route)
        guard route != store.settings.linkRoutes[i] else { return }
        store.settings.linkRoutes[i] = route
    }

    /// A new empty route at the bottom, its URL field taking the keyboard (and scrolled to).
    private func addRoute() {
        let route = LinkRoute()
        store.settings.linkRoutes.append(route)
        rebuild()
        _ = try? fields[route.id]?.focus(.programmatic)
    }

    private func removeRoute(_ id: UUID) {
        store.settings.linkRoutes.removeAll { $0.id == id }
        rebuild()
        _ = try? newRoute.focus(.programmatic)
    }
}

/// A destination menu's items, checked to follow the choice.
@MainActor
private final class MenuChecks {
    var items: [(LinkDestination, ToggleMenuFlyoutItem)] = []

    func check(_ destination: LinkDestination) {
        for (d, item) in items { item.isChecked = d == destination }
    }
}
