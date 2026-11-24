import Foundation

/// Arc's Split View Options menu on a split pane's bar (PaneToolbarView.showSplitMenu, Arc 1.171):
/// the entries in order, each with the command it runs; nil is a separator. The bar focuses its
/// pane first, so Flip and Copy Link act on it.
public enum SplitPaneOptionsMenu {
    public struct Entry: Equatable, Sendable {
        public let title: String
        /// The command's id ("separateFromSplit", "flipSplitOrientation", "copyURL", "closeSplitPane"),
        /// which also names its shortcut.
        public let action: String
    }

    public static let entries: [Entry?] = [
        Entry(title: "Separate Tab from Split", action: "separateFromSplit"),
        Entry(title: "Flip Split View Orientation", action: "flipSplitOrientation"),
        nil,
        Entry(title: "Copy Link", action: "copyURL"),
        nil,
        Entry(title: "Close this Split Pane", action: "closeSplitPane"),
    ]

    /// Whether a split pane's bar shows: a pane of a split (more than one pane) outside HTML
    /// fullscreen. A split's panes always have their bars, View ▸ Show Toolbar or not
    /// (ShellView.barsShown).
    public static func barsShown(panes: Int, fullscreen: Bool) -> Bool { panes > 1 && !fullscreen }
}
