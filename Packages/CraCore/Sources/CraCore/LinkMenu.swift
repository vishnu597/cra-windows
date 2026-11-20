import Foundation

/// The "Open Link in New Tab" item on a page's context menu. Arc has one, and it leaves the page
/// in front with the new tab loading behind it (measured in Arc 1.172, 9 Nov 2026, GitHub #276);
/// so does Cra's, unless Settings ▸ Tabs ▸ "“Open Link in New Tab” switches to the new tab" is on.
/// ⌘-click (background) and ⇧⌘-click (switch) say what they want and don't follow the setting;
/// neither does a target=_blank click, which the page asked for.
public enum LinkMenu {
    public struct Item: Equatable, Sendable {
        public let title: String
        public let opensInBackground: Bool
    }

    /// The title where Chromium's own isn't to hand.
    public static let newTabTitle = "Open Link in New Tab"

    /// `newTabTitle` is Chromium's own "Open Link in New Tab", in the language Chromium runs in, as
    /// Arc shows it (#276).
    public static func item(switchesToTab: Bool, newTabTitle: String = newTabTitle) -> Item {
        Item(title: newTabTitle, opensInBackground: !switchesToTab)
    }
}

/// What a page's link menu adds under Open Link in New Window (Arc's order, #257, #276): Open Link
/// in Split View where the page has a tab to split (a browser window's, not a Little Window's or a
/// Peek's), then Open Link in Little Window, which a private page doesn't offer. The Mac's bridge
/// (BuildArcMenu) and Windows' CraCEFWin show these.
public enum LinkMenuExtra: Int, CaseIterable, Sendable {
    case splitView = 1
    case littleWindow = 2

    public var title: String {
        switch self {
        case .splitView: "Open Link in Split View"
        case .littleWindow: "Open Link in Little Window"
        }
    }

    public static func offered(splits: Bool, incognito: Bool) -> [LinkMenuExtra] {
        (splits ? [.splitView] : []) + (incognito ? [] : [.littleWindow])
    }

    /// The items as bits (`rawValue`), for a C bridge.
    public static func mask(_ extras: [LinkMenuExtra]) -> Int32 {
        extras.reduce(0) { $0 | Int32($1.rawValue) }
    }
}
