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
