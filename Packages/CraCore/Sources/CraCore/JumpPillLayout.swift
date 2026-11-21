import Foundation

/// Dia's "back to the open tab" pill (TabList.TabOverflowIndicatorView, its geometry from
/// TabOverflowGeometryTracker): while the selected tab's row is scrolled out of the sidebar's
/// list, a dark capsule with its favicon and an arrow pointing at it sits 7 pt inside the edge the
/// tab is past. A click scrolls the tab to the middle of the list. Coordinates run down from the
/// list's top, as AppKit's flipped views and XAML both draw them.
///
/// Measured on a Dia capture (2x): a 51 × 28 pt capsule, fill #1F1C1C (#2A2727 hovered), a
/// 0.5 pt light inner edge inside a 0.5 pt dark outer edge; 10.5 pt in, the 16 pt favicon, 7 pt,
/// a thin 7 pt wide arrow in #ADACAC, 10.5 pt out. A split shows up to three favicons, each
/// overlapping the one before by 5 pt.
public enum JumpPillLayout {
    public enum Edge: Equatable, Sendable { case top, bottom }

    /// From the list edge to the pill.
    public static let inset: CGFloat = 7
    public static let height: CGFloat = 28
    public static let padding: CGFloat = 10.5
    public static let icon: CGFloat = 16
    public static let overlap: CGFloat = 5
    /// Between the last favicon and the arrow, and the arrow's own width.
    public static let gap: CGFloat = 7
    public static let arrowWidth: CGFloat = 7
    /// A split's favicons past this many aren't drawn.
    public static let maxIcons = 3
    public static let fill: UInt32 = 0x1F1C1C
    public static let fillHovered: UInt32 = 0x2A2727
    public static let arrowColor: UInt32 = 0xADACAC

    /// The edge the pill shows at: the one the selected row is wholly past. Nil while any of it
    /// is in sight, or while the list has no height yet.
    public static func edge(rowTop: CGFloat, rowBottom: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat) -> Edge? {
        guard visibleBottom > visibleTop else { return nil }
        if rowBottom <= visibleTop { return .top }
        if rowTop >= visibleBottom { return .bottom }
        return nil
    }

    /// The pill's width for these many favicons (at least one, at most `maxIcons`).
    public static func width(icons n: Int) -> CGFloat {
        let shown = min(max(1, n), maxIcons)
        let iconsWidth = icon + CGFloat(shown - 1) * (icon - overlap)
        return (padding + iconsWidth + gap + arrowWidth + padding).rounded(.up)
    }

    /// Where the list scrolls on a click: the row's middle at the list's middle, kept inside
    /// what the content can scroll.
    public static func scrollTarget(rowTop: CGFloat, rowBottom: CGFloat, visibleHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let middle = (rowTop + rowBottom) / 2
        return min(max(0, middle - visibleHeight / 2), max(0, contentHeight - visibleHeight))
    }
}
