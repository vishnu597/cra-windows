import Foundation

/// The Library's Spaces page, which "Manage Spaces…" opens (Arc 1.171's spaceManager): every
/// space as a card in its own theme, side by side, to reorder or edit. Windows' Library draws it
/// from this; the Mac's SpacesManagerView has the same numbers in SpacesManagerMetrics.
///
/// Measured from a 2x capture of Arc's window (1 Nov 2026): every card is 240 pt wide, 24 pt
/// apart, starting 27 pt right of the rail, 48 pt below the window's top and above its bottom.
/// A New Space + (29 pt) sits 34 pt after the last card, 37.5 pt before the page's edge.
public enum SpacesManagerLayout {
    public static let card = 240.0
    public static let gap = 24.0
    public static let lead = 27.0
    public static let inset = 48.0
    public static let plus = 29.0
    public static let plusGap = 34.0
    public static let trail = 37.5
    /// The card's header row (icon, name) is centred 25 pt down; its pinned list starts 40.5 pt
    /// down and its footer (move handle, ⋯) is centred 21 pt above the bottom.
    public static let headerCentre = 25.0
    public static let listTop = 40.5
    public static let footerHeight = 42.0

    /// One card dragged in the strip's fixed viewport coordinates (DIPs), not in the
    /// translated card's coordinates. Scrolling the viewport moves the card's content origin
    /// too. Its translation stops at the first/last real card instead of following the pointer
    /// arbitrarily far beyond the strip.
    public struct Drag: Equatable, Sendable {
        private let pointerX: Double
        private let scrollOffset: Double
        private let minimum: Double
        private let maximum: Double

        public init(pointerX: Double, scrollOffset: Double, index: Int, count: Int) {
            self.pointerX = pointerX
            self.scrollOffset = scrollOffset
            let last = max(0, count - 1)
            let start = min(max(0, index), last)
            let pitch = SpacesManagerLayout.card + SpacesManagerLayout.gap
            minimum = -Double(start) * pitch
            maximum = Double(last - start) * pitch
        }

        public func offset(pointerX: Double, scrollOffset: Double) -> Double {
            let moved = pointerX - self.pointerX + scrollOffset - self.scrollOffset
            return min(maximum, max(minimum, moved))
        }
    }

    /// The width the cards need with the Library's rail (`rail` wide) on their left: what
    /// `LibraryWidth.sidebar(spacesCards:window:)` widens the Library to.
    public static func width(spaces n: Int, rail: Double) -> Double {
        rail + lead + Double(n) * card + Double(max(0, n - 1)) * gap + plusGap + plus + trail
    }

    /// The spaces the page shows, in the dock's order: not an incognito or Blank Window's own.
    public static func spaces(order: [UUID], standalone: (UUID) -> Bool) -> [UUID] {
        order.filter { !standalone($0) }
    }

    /// Where a card let go `dx` points from where it started lands among the `shown` cards: its
    /// centre's place, one card per card and gap. Returns the index into `spaceOrder` to pass to
    /// `SidebarStore.moveSpace(_:to:)`, or nil when the card stays where it was.
    public static func drop(_ id: UUID, dx: Double, shown: [UUID], spaceOrder: [UUID]) -> Int? {
        move(id, by: Int((dx / (card + gap)).rounded()), shown: shown, spaceOrder: spaceOrder)
    }

    /// The card `steps` places along (Windows' Move Left and Move Right, a keyboard's way to
    /// reorder): the index into `spaceOrder` for `SidebarStore.moveSpace(_:to:)`, or nil when
    /// it can't go further.
    public static func move(_ id: UUID, by steps: Int, shown: [UUID], spaceOrder: [UUID]) -> Int? {
        guard let from = shown.firstIndex(of: id) else { return nil }
        let to = min(max(0, from + steps), shown.count - 1)
        guard to != from else { return nil }
        return spaceOrder.firstIndex(of: shown[to])
    }
}
