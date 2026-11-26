import Foundation

/// Arc's tab switcher (ModalItemSwitcher) on ⌃Tab (Ctrl+Tab on Windows): the space's most
/// recent tabs as cards, the way ⌘Tab / Alt+Tab shows apps. The first press opens it on the
/// next card (⌃⇧Tab: the last), more presses and the arrows move round, releasing the held key
/// switches, Escape cancels. One open tab shows its only card; none opens nothing. The Mac's
/// TabSwitcher reads the same rules; this holds the cards and the selection for Windows.
public struct TabSwitcherCycle: Equatable, Sendable {
    public private(set) var items: [UUID] = []
    public private(set) var selectedIndex = 0

    public init() {}

    public var isOpen: Bool { !items.isEmpty }
    public var selected: UUID? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    /// The switcher's first press. False, and nothing opens, without tabs.
    public mutating func open(_ cards: [UUID], delta: Int) -> Bool {
        guard !cards.isEmpty else { return false }
        items = cards
        selectedIndex = cards.count == 1 ? 0 : delta > 0 ? 1 : cards.count - 1
        return true
    }

    /// Tab / Shift+Tab and the arrows, round the ends.
    public mutating func move(_ delta: Int) {
        let n = items.count
        guard n > 0 else { return }
        selectedIndex = ((selectedIndex + delta) % n + n) % n
    }

    /// The pointer over a card, or a click on one.
    public mutating func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Closes it. `commit` (the key let go, Return, a click on a card) answers the tab to
    /// switch to; a cancel (Escape, a click elsewhere) answers nil.
    public mutating func close(commit: Bool) -> UUID? {
        let chosen = commit ? selected : nil
        items = []
        selectedIndex = 0
        return chosen
    }

    /// The cards: the space's recent tabs, most recent first (`SidebarStore.recentTabs`),
    /// leaving out pinned tabs without a page (unloaded) unless it's the open one, at most
    /// `TabSwitcherLayout.maxItems` (MainWindowController.openRecentTabs).
    public static func cards(recent: [UUID], selected: UUID?, isPinned: (UUID) -> Bool, isLoaded: (UUID) -> Bool,
                             limit: Int = TabSwitcherLayout.maxItems) -> [UUID] {
        Array(recent.filter { $0 == selected || !isPinned($0) || isLoaded($0) }.prefix(limit))
    }

    /// The same rule for cards that may be splits (#554): a split's card stays while any of its
    /// panes is open (MainWindowController.openRecentCards, Windows' BrowserWindow).
    /// A Favorite closed with ⌘W whose page kept running leaves the switcher until it's picked again (#784,
    /// `RecentTabOrder.listsPane`).
    public static func cards(_ recent: [RecentTabOrder.Card], selected: UUID?, isPinned: (UUID) -> Bool,
                             isLoaded: (UUID) -> Bool, closedWithCmdW: (UUID) -> Bool = { _ in false },
                             limit: Int = TabSwitcherLayout.maxItems) -> [RecentTabOrder.Card] {
        Array(recent.filter { card in
            card.panes.contains {
                RecentTabOrder.listsPane(selected: $0 == selected, pinned: isPinned($0), loaded: isLoaded($0), closedWithCmdW: closedWithCmdW($0))
            }
        }.prefix(limit))
    }
}

/// Arc 1.170's tab switcher, measured on a 1× display (27 Oct 2026, see
/// docs/arc-reverse-engineering.md "Tab switcher"), in points (DIPs on Windows).
public enum TabSwitcherLayout {
    public static let maxItems = 5
    /// ⌃Tab to panel: Arc showed it 0.18–0.26 s after the key; a 0.13 s tap never showed it.
    public static let showDelay: TimeInterval = 0.15
    public static let card = CGSize(width: 180, height: 158)
    public static let thumbnail = CGSize(width: 158, height: 105)
    public static let thumbnailOrigin = CGPoint(x: 11.5, y: 12)
    public static let cardSpacing: CGFloat = 2
    public static let paddingH: CGFloat = 16.5
    public static let paddingV: CGFloat = 16
    public static let cornerRadius: CGFloat = 26
    public static let cardCornerRadius: CGFloat = 8
    public static let thumbnailCornerRadius: CGFloat = 6.5
    public static let paneCornerRadius: CGFloat = 4.5
    public static let favicon: CGFloat = 16
    /// Room around the panel for its shadow (the window is this much larger on each side).
    public static let shadowMargin: CGFloat = 40

    public static func panelSize(count: Int) -> CGSize {
        let n = CGFloat(max(count, 1))
        return CGSize(width: paddingH * 2 + n * card.width + (n - 1) * cardSpacing, height: paddingV * 2 + card.height)
    }

    public static func windowSize(count: Int) -> CGSize {
        let p = panelSize(count: count)
        return CGSize(width: p.width + shadowMargin * 2, height: p.height + shadowMargin * 2)
    }
}

public extension SpaceTheme {
    /// The selected card: Arc's semantic "hover" colour. In Arc's own data (JYSK and Victor
    /// spaces) the dark one sits at OKLab lightness ≈ 0.60 in the theme's hue, close to the
    /// most saturated colour sRGB has there, at 48% opacity; the light one is opaque at ≈ 0.885.
    func switcherHighlightRGBA(dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        let hex = accent ?? colors.first ?? "#808080"
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        let lab = OKLab.from(r: c.r, g: c.g, b: c.b)
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        let hue = atan2(lab.b, lab.a)
        let L = dark ? 0.60 : 0.885
        // Greys stay grey; anything with a clear hue gets Arc's near-full saturation.
        let target = OKLab.maxChroma(L: L, hue: hue) * (dark ? 0.87 : 0.5) * min(1, chroma / 0.03)
        let rgb = OKLab.toRGB(L: L, a: target * cos(hue), b: target * sin(hue))
        return (rgb.r, rgb.g, rgb.b, dark ? 0.48 : 1)
    }
}
