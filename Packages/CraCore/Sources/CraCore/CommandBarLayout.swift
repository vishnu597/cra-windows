import Foundation

/// Arc's command bar in points (upstream 3bd548d, Arc 1.172.1 measured live): a 64 pt field over rows 46
/// tall, 4 apart, 10 in from the sides, from 6 under the field to 12 above the bar's edge, 766 wide in a
/// browser window. The Mac's CommandBarView and Windows' (in DIPs) lay out with these.
public enum CommandBarLayout {
    public static let width: Double = 766
    public static let fieldHeight: Double = 64
    public static let rowHeight: Double = 46
    public static let rowGap: Double = 4
    public static let rowInset: Double = 10
    public static let rowsTop: Double = 6
    public static let rowsBottom: Double = 12
    /// Arc's info badge right of the empty field: a 24 pt circle 21 pt from the edge.
    public static let badgeSize: Double = 24
    public static let badgeTrailing: Double = 21
    /// The scope's pill: 23 tall, fully round, 10.5 pt around the name.
    public static let pillHeight: Double = 23
    public static let pillPadding: Double = 10.5

    /// The bar's height with `n` rows (the field alone with none).
    public static func height(forRows n: Int) -> Double {
        fieldHeight + (n == 0 ? 0 : Double(n) * rowHeight + Double(n - 1) * rowGap + rowsTop + rowsBottom)
    }
}
