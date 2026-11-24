import Foundation

/// What the toolbar's address shows (PaneToolbarView's host and path): the site alone, as Arc
/// does unless "Show Full URL" is on (#88), then the rest of the address dimmed after it. An
/// easel's bar shows the easel's name.
public enum ToolbarAddress {
    public static func parts(url: String, showFullURL: Bool, easelTitle: String? = nil) -> (host: String, path: String) {
        if Easel.id(fromURL: url) != nil, let easelTitle { return (easelTitle, "") }
        let human = SuggestionEngine.humanURL(url)
        let host = AppSettings.siteKey(for: url) ?? human
        return (host, showFullURL && human.hasPrefix(host) ? String(human.dropFirst(host.count)) : "")
    }
}

/// Which bar a window with one strip over its pages shows there (Windows: HostWindow's top strip).
/// The developer bar wins whenever the page is in Developer Mode, as the Mac's toolbar turns into it;
/// the normal toolbar shows with View ▸ Show Toolbar, and neither over a split, whose panes would
/// each carry their own (Arc disables Show Toolbar's bar while a split is open, GitHub #178).
public enum WindowTopBar: Equatable, Sendable {
    case none, toolbar, developer

    public static func resolve(showToolbar: Bool, developerMode: Bool, paneCount: Int, hasURL: Bool) -> WindowTopBar {
        guard paneCount <= 1 else { return .none }
        if developerMode, hasURL { return .developer }
        return showToolbar ? .toolbar : .none
    }
}

/// The menu a right-click on ↻ shows (PR #517, the Mac's ReloadMenu): its commands by id, in
/// groups split by separators. The toolbar's ↻ and the sidebar header's carry it.
public enum ReloadMenuItems {
    public static let groups: [[String]] = [["reload", "hardReload"], ["clearCookies", "clearCache"], ["viewSource", "devTools"]]
}

/// The menu a right-click on the toolbar's address shows (PaneToolbarView.addressMenu, Arc 1.172.1):
/// Copy URL, Capture…, Capture Full Page, Manage Extensions…, then Show or Hide Full URL, Automatically
/// Hide Toolbar (the page's own bar only, not a split pane's) and Hide Toolbar. Arc's Share ▸ is in the
/// Site Control Center, and Shared Quotes go through arc.net, so neither is listed.
public enum ToolbarAddressMenu {
    public enum Row: Equatable, Sendable {
        /// A KeyBindings command by id, with its title.
        case command(String, String)
        /// Show Full URL, or Hide Full URL while it shows.
        case fullURL(showing: Bool)
        /// Automatically Hide Toolbar, ticked while on.
        case autoHide(on: Bool)
        case separator
    }

    public static func rows(showFullURL: Bool, autoHide: Bool, panes: Int = 1) -> [Row] {
        var rows: [Row] = [.command("copyURL", "Copy URL"), .command("capturePage", "Capture…"),
                           .command("captureFullPage", "Capture Full Page"), .separator,
                           .command("manageExtensions", "Manage Extensions…"), .separator,
                           .fullURL(showing: showFullURL)]
        if panes <= 1 { rows.append(.autoHide(on: autoHide)) }
        rows.append(.command("toggleToolbar", "Hide Toolbar"))
        return rows
    }
}
