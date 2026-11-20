import CraCore
import Foundation
import UWP
import WinUI

/// Arc's space icon picker (the Mac's SpaceIconPicker): Emoji and Icon tabs and a trash button
/// (Remove Icon), a search field over an 8-wide emoji grid that opens on the current emoji's row,
/// and a category bar. In a Flyout at the space's icon. Every control is kept here: a WinRT
/// control made in Swift is only a wrapper, and a weak capture of one is nil once Swift lets go.
@MainActor
final class SpaceIconPickerView {
    static let columns = 8
    static let cell = 31.0
    static let size = 272.0

    let flyout = Flyout()
    private let root = Grid()
    private let tabs = StackPanel()
    private let emojiTab = Button()
    private let iconTab = Button()
    private let trash = Button()
    private let search = TextBox()
    private let emojiPage = Grid()
    private let emojiScroll = ScrollViewer()
    private let emojiRows = StackPanel()
    private let categories = StackPanel()
    private let iconScroll = ScrollViewer()
    private let iconRows = StackPanel()
    private var rows: [Grid] = []
    /// What each emoji row shows, for the press that picks from it.
    private var shown: [[EmojiCatalog.Entry]] = []
    private let current: SpaceIcon
    private let onPick: @MainActor (SpaceIcon) -> Void
    private let ink: Brush
    private let faint: Brush
    private let tile: Brush

    /// The Icon tab: the picker's symbols that Segoe Fluent Icons can draw, in its order.
    static var symbols: [String] { SpaceIcon.pickerSymbols.filter { WinGlyph.known($0) != nil } }

    init(current: SpaceIcon, dark: Bool, onPick: @escaping @MainActor (SpaceIcon) -> Void) {
        self.current = current
        self.onPick = onPick
        ink = dark ? UI.brush(255, 255, 255) : UI.brush(20, 20, 24)
        faint = dark ? UI.brush(255, 255, 255, alpha: 150) : UI.brush(20, 20, 24, alpha: 150)
        tile = dark ? UI.brush(255, 255, 255, alpha: 40) : UI.brush(0, 0, 0, alpha: 30)
        root.width = Self.size
        root.height = Self.size + 20
        for height in [UI.auto, UI.star] { root.rowDefinitions.append(UI.row(height)) }

        // The tabs and the trash.
        tabs.orientation = .horizontal
        tabs.spacing = 6
        tabs.horizontalAlignment = .center
        tabs.margin = Thickness(left: 0, top: 4, right: 0, bottom: 6)
        emojiTab.content = UI.text("Emoji", size: 12, trimmed: false)
        iconTab.content = UI.text("Icon", size: 12, trimmed: false)
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code("trash")
        glyph.fontSize = 14
        trash.content = glyph
        try? ToolTipService.setToolTip(trash, "Remove Icon")
        try? AutomationProperties.setName(trash, "Remove Icon")
        for b in [emojiTab, iconTab, trash] { tabs.children.append(b) }
        emojiTab.click.addHandler { [weak self] _, _ in self?.showTab(icons: false) }
        iconTab.click.addHandler { [weak self] _, _ in self?.showTab(icons: true) }
        trash.click.addHandler { [weak self] _, _ in self?.pick(.none) }
        root.children.append(tabs)

        // Emoji: search, the grid, the category bar.
        for height in [UI.auto, UI.star, UI.auto] { emojiPage.rowDefinitions.append(UI.row(height)) }
        search.placeholderText = "Search"
        search.margin = Thickness(left: 8, top: 0, right: 8, bottom: 6)
        try? AutomationProperties.setName(search, "Search emoji")
        search.textChanged.addHandler { [weak self] _, _ in self?.fillEmoji() }
        emojiScroll.content = emojiRows
        emojiRows.orientation = .vertical
        emojiRows.horizontalAlignment = .center
        categories.orientation = .horizontal
        categories.horizontalAlignment = .center
        for category in EmojiCatalog.categories {
            guard let first = category.entries.first else { continue }
            let b = UI.button(UI.text(first.emoji, size: 14, trimmed: false), padding: Thickness(left: 4, top: 2, right: 4, bottom: 2)) { [weak self] in
                self?.scrollTo(first.emoji, clearing: true)
            }
            b.opacity = 0.7
            try? AutomationProperties.setName(b, category.id)
            categories.children.append(b)
        }
        let parts: [FrameworkElement] = [search, emojiScroll, categories]
        for (i, part) in parts.enumerated() {
            emojiPage.children.append(part)
            try? Grid.setRow(part, Int32(i))
        }
        root.children.append(emojiPage)
        try? Grid.setRow(emojiPage, 1)

        // Icon: Arc's glyphs and Cra's extras that Windows' icon font has.
        iconScroll.content = iconRows
        iconRows.orientation = .vertical
        iconRows.horizontalAlignment = .center
        fillIcons()
        root.children.append(iconScroll)
        try? Grid.setRow(iconScroll, 1)

        flyout.content = root
        // A windowed popup: over the page's own window, which XAML inside the island would sit under.
        flyout.shouldConstrainToRootBounds = false
        flyout.opened.addHandler { [weak self] _, _ in self?.opened() }
        fillEmoji()
        showTab(icons: current.symbol != nil)
    }

    func show(at anchor: FrameworkElement) {
        try? flyout.showAt(anchor)
    }

    private func pick(_ icon: SpaceIcon) {
        try? flyout.hide()
        onPick(icon)
    }

    private func showTab(icons: Bool) {
        emojiPage.visibility = icons ? .collapsed : .visible
        iconScroll.visibility = icons ? .visible : .collapsed
        emojiTab.opacity = icons ? 0.6 : 1
        iconTab.opacity = icons ? 1 : 0.6
    }

    /// Opens on the current emoji's row (EmojiCatalog.rowStart), the field taking the keys.
    private func opened() {
        if case .emoji(let e) = current { scrollTo(e, clearing: false) }
        if emojiPage.visibility == .visible { _ = try? search.focus(.programmatic) }
    }

    private func scrollTo(_ emoji: String, clearing: Bool) {
        if clearing && !search.text.isEmpty { search.text = "" }
        guard let start = EmojiCatalog.rowStart(of: emoji, columns: Self.columns),
              let row = shown.firstIndex(where: { $0.first?.emoji == start }) else { return }
        _ = try? emojiScroll.changeView(nil, Double(row) * Self.cell, nil, true)
    }

    /// The grid: every emoji in one run across the categories, as in Arc, or what the search finds.
    private func fillEmoji() {
        let query = search.text
        let entries = query.isEmpty ? EmojiCatalog.all : EmojiCatalog.search(query)
        shown = stride(from: 0, to: entries.count, by: Self.columns).map { Array(entries[$0..<min($0 + Self.columns, entries.count)]) }
        emojiRows.children.clear()
        rows = []
        let currentEmoji = current.emoji
        for (r, entries) in shown.enumerated() {
            let row = Grid()
            row.height = Self.cell
            row.background = UI.clear
            for _ in 0..<Self.columns { row.columnDefinitions.append(UI.column(UI.pixels(Self.cell))) }
            for (c, entry) in entries.enumerated() {
                let box = Border()
                box.cornerRadius = CornerRadius(topLeft: 5, topRight: 5, bottomRight: 5, bottomLeft: 5)
                box.margin = Thickness(left: 1.75, top: 1.75, right: 1.75, bottom: 1.75)
                if entry.emoji == currentEmoji { box.background = tile }
                let t = UI.text(entry.emoji, size: 19, trimmed: false)
                t.horizontalAlignment = .center
                t.verticalAlignment = .center
                box.child = t
                row.children.append(box)
                try? Grid.setColumn(box, Int32(c))
            }
            // One press handler a row: the column under the pointer.
            row.pointerPressed.addHandler { [weak self, r] _, args in
                guard let self, let args, r < self.shown.count, let point = try? args.getCurrentPoint(self.rows[r]) else { return }
                let c = Int(Double(point.position.x) / Self.cell)
                guard c >= 0, c < self.shown[r].count else { return }
                args.handled = true
                self.pick(.emoji(self.shown[r][c].emoji))
            }
            rows.append(row)
            emojiRows.children.append(row)
        }
        if shown.isEmpty { emojiRows.children.append(UI.text("No emoji found", size: 12, color: faint)) }
    }

    private func fillIcons() {
        let symbols = Self.symbols
        let currentSymbol = current.symbol
        for start in stride(from: 0, to: symbols.count, by: Self.columns) {
            let row = StackPanel()
            row.orientation = .horizontal
            for name in symbols[start..<min(start + Self.columns, symbols.count)] {
                let icon = FontIcon()
                icon.glyph = WinGlyph.known(name) ?? ""
                icon.fontSize = 14
                icon.foreground = ink
                let b = UI.button(icon, fill: name == currentSymbol ? tile : nil, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
                    self?.pick(.symbol(name))
                }
                b.width = Self.cell
                b.height = Self.cell
                try? AutomationProperties.setName(b, name)
                row.children.append(b)
            }
            iconRows.children.append(row)
        }
    }
}
