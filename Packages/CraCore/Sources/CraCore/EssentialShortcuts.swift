import Foundation

/// Arc's Help ▸ Essential Keyboard Shortcuts card (KeyboardShortcutsEDUWindowController, Arc 1.172.1,
/// captured 7 Nov 2026 at 2x): five rows, each a title, a grey line under it, and the action's own keys
/// as caps on the right. The Mac's EssentialShortcutsWindow and Windows' card read these.
public enum EssentialShortcuts {
    public struct Row: Equatable, Sendable {
        /// The KeyBindings action whose keys the row shows (the user's own).
        public let action: String
        public let title: String
        public let detail: String
    }

    /// Arc's five, with Cra's action for each.
    public static let rows: [Row] = [
        Row(action: "newTab", title: "Open a New Tab", detail: "Open the Command Bar to create a new tab"),
        Row(action: "recentTab", title: "Switch to a Recent Tab", detail: "Hold this to quickly switch between recent tabs"),
        Row(action: "copyURL", title: "Copy Page URL", detail: "Copy the current tab's URL without trackers"),
        Row(action: "addSplitView", title: "Add Split View", detail: "View multiple websites side-by-side"),
        Row(action: "newLittleWindow", title: "Open Little Window", detail: "Use a smaller browser window for quick searches"),
    ]

    /// Points: Arc's card is 475 × 462, its rows 73 apart under a 20.5 pt heavy title.
    public static let width: Double = 475
    public static let height: Double = 462
}

public extension KeyChord {
    /// The keys as Windows' card draws them, one cap each: "Ctrl", "Shift", "T" (`windowsDisplay` split).
    var windowsCaps: [String] { windowsDisplay.split(separator: "+").map(String.init) }
}
