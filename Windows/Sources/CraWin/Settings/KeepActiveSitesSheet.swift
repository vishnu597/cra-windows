import CraCore
import Foundation
import UWP
import WinAppSDK
import WinUI

/// Settings ▸ Tabs ▸ Memory ▸ "Always keep these sites active" (GitHub #458; KeepActiveSitesView on
/// the Mac), drawn as Air Traffic Control's sheet is: the title and an address field with Add, one
/// row per site (its host, whether its subdomains count, a remove button), and the note. Escape,
/// the ✕ or a click beside the card closes it, and the list is tidied then.
@MainActor
final class KeepActiveSitesSheet {
    /// Covers the whole window, dimming it; collapsed while the sheet is closed.
    let root = Grid()
    private let store: SidebarStore
    private let palette: SettingsPalette
    private let card = Border()
    private let rows = StackPanel()
    private let emptyNote: TextBlock
    private let field = TextBox()
    private var addButton: Button!
    /// The rows' controls, which their handlers capture weakly (a WinRT control made from Swift
    /// is only a wrapper).
    private var kept: [AnyObject] = []
    private weak var opener: Button?

    var isShown: Bool { root.visibility == .visible }

    init(store: SidebarStore, palette: SettingsPalette) {
        self.store = store
        self.palette = palette
        emptyNote = UI.text("No sites yet. Type an address above, or pick a site a tab has open.", size: 12,
                            color: palette.secondaryText, trimmed: false)
        root.visibility = .collapsed
        root.background = UI.brush(0, 0, 0, alpha: palette.isDark ? 110 : 60)
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
        card.tabFocusNavigation = .cycle
        card.tapped.addHandler { _, args in args?.handled = true }
        root.children.append(card)

        let layout = Grid()
        layout.rowDefinitions.append(UI.row(UI.pixels(84)))
        layout.rowDefinitions.append(UI.row(UI.pixels(1)))
        layout.rowDefinitions.append(UI.row(UI.auto))
        layout.rowDefinitions.append(UI.row(UI.star))
        layout.rowDefinitions.append(UI.row(UI.pixels(1)))
        layout.rowDefinitions.append(UI.row(UI.auto))
        card.child = layout

        layout.children.append(makeHeader())
        for row in [Int32(1), 4] {
            let line = Border()
            line.background = palette.hairline
            layout.children.append(line)
            try? Grid.setRow(line, row)
        }

        let entry = Grid()
        entry.margin = Thickness(left: 0, top: 16, right: 0, bottom: 4)
        entry.columnDefinitions.append(UI.column(UI.star))
        entry.columnDefinitions.append(UI.column(UI.auto))
        field.placeholderText = "example.com"
        field.verticalAlignment = .center
        field.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x0D else { return }
            args.handled = true
            self.add(self.field.text)
        }
        try? AutomationProperties.setName(field, "Site address")
        entry.children.append(field)
        let add = Button()
        add.content = UI.text("Add Site", trimmed: false)
        add.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
        add.verticalAlignment = .center
        add.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.add(self.field.text)
        }
        addButton = add
        entry.children.append(add)
        try? Grid.setColumn(add, 1)
        layout.children.append(entry)
        try? Grid.setRow(entry, 2)

        let middle = Grid()
        let scroll = ScrollViewer()
        rows.orientation = .vertical
        rows.spacing = 10
        rows.padding = Thickness(left: 0, top: 12, right: 0, bottom: 12)
        scroll.content = rows
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
        try? Grid.setRow(middle, 3)

        let note = UI.text("“example.com” with its subdomains also covers app.example.com, never notexample.com. The same list is at chrome://settings/performance.",
                           size: 11, color: palette.secondaryText, trimmed: false)
        note.textWrapping = .wrap
        note.margin = Thickness(left: 0, top: 14, right: 0, bottom: 14)
        layout.children.append(note)
        try? Grid.setRow(note, 5)
    }

    /// Opens with the keyboard in the address field.
    func show(from opener: Button?) {
        self.opener = opener
        field.text = ""
        rebuild()
        root.visibility = .visible
        _ = try? field.focus(.programmatic)
    }

    func hide() {
        guard isShown else { return }
        root.visibility = .collapsed
        store.settings.tidyKeepActiveSites()
        rows.children.clear()
        kept.removeAll()
        _ = try? opener?.focus(.programmatic)
    }

    private func makeHeader() -> Grid {
        let header = Grid()
        header.padding = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        header.columnDefinitions.append(UI.column(UI.star))
        header.columnDefinitions.append(UI.column(UI.auto))
        let titles = StackPanel()
        titles.orientation = .vertical
        titles.spacing = 2
        titles.verticalAlignment = .center
        let title = UI.text("Always keep these sites active", color: palette.text)
        title.fontWeight = UWP.FontWeight(weight: 700)
        titles.children.append(title)
        titles.children.append(UI.text("Their tabs stay in memory and keep running while hidden.", size: 11, color: palette.secondaryText))
        header.children.append(titles)
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
        try? Grid.setColumn(close, 1)
        return header
    }

    private func add(_ text: String) {
        guard store.settings.addKeepActiveSite(text) != nil else { return }
        field.text = ""
        rebuild()
        _ = try? field.focus(.programmatic)
    }

    private func rebuild() {
        rows.children.clear()
        kept.removeAll()
        for site in store.settings.keepActiveSites { rows.children.append(row(site)) }
        emptyNote.visibility = store.settings.keepActiveSites.isEmpty ? .visible : .collapsed
    }

    private func row(_ site: KeepActiveSite) -> UIElement {
        let id = site.id
        let row = Grid()
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        row.columnDefinitions.append(UI.column(UI.auto))
        let host = UI.text(site.normalizedHost ?? site.host, color: palette.text)
        host.verticalAlignment = .center
        row.children.append(host)

        let scope = ComboBox()
        scope.items.append("and its subdomains")
        scope.items.append("this address only")
        scope.selectedIndex = site.scopeLabel == "and its subdomains" ? 0 : 1
        scope.verticalAlignment = .center
        scope.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
        scope.selectionChanged.addHandler { [weak self, weak scope] _, _ in
            guard let self, let scope, let i = self.store.settings.keepActiveSites.firstIndex(where: { $0.id == id }) else { return }
            var s = self.store.settings.keepActiveSites[i]
            // The switch decides: the host alone, so a typed `*.` or `.` doesn't overrule it.
            s.host = KeepActiveSite.parse(s.host)?.host ?? s.host
            s.includesSubdomains = scope.selectedIndex == 0
            self.store.settings.keepActiveSites[i] = s
        }
        try? AutomationProperties.setName(scope, "Subdomains")
        row.children.append(scope)
        try? Grid.setColumn(scope, 1)

        let minus = FontIcon()
        minus.glyph = "\u{ECC9}"  // RemoveFrom: a minus in a circle
        minus.fontSize = 14
        minus.foreground = palette.secondaryText
        let remove = UI.button(minus, padding: Thickness(left: 4, top: 4, right: 4, bottom: 4)) { [weak self] in
            guard let self else { return }
            self.store.settings.keepActiveSites.removeAll { $0.id == id }
            self.rebuild()
        }
        remove.verticalAlignment = .center
        remove.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
        try? AutomationProperties.setName(remove, "Remove")
        try? ToolTipService.setToolTip(remove, "Remove")
        row.children.append(remove)
        try? Grid.setColumn(remove, 2)
        kept.append(scope)
        kept.append(remove)
        return row
    }
}
