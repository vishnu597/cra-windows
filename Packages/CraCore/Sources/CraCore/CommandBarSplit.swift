import Foundation

/// The page a command bar row opens anew, in a background tab (⌘Return, Ctrl+Return on Windows) or
/// a split pane (⌥Return, Alt+Return): nil for rows that open no page (commands, spaces, folders).
@MainActor
public enum CommandBarRowPage {
    /// `typed` is what Return goes to (the field, its completion accepted); `query` what was typed.
    public static func url(row: Suggestion?, typed: String, query: String, searchURL: @MainActor (String) -> String) -> String? {
        let url: String?
        switch row?.kind {
        case nil:
            url = typed.isEmpty ? nil : TypedURL.looksLikeURL(typed) ? TypedURL.fromInput(typed) : searchURL(typed)
        case .navigate?:
            url = TypedURL.navigation(typed: typed, rowURL: row?.url, rowIsForTyped: typed == query) ?? searchURL(typed)
        case .search?:
            url = row?.url ?? searchURL(typed)
        case .switchToTab?, .archived?, .history?, .topDomain?:
            url = row?.url
        default:
            url = nil
        }
        return url?.isEmpty == false ? url : nil
    }
}

/// What ⌥Return (Alt+Return on Windows) in the command bar did.
public enum CommandBarSplitOutcome: Equatable, Sendable {
    /// Not a split to make: no tab, an empty one (the row fills it), a tab of another space, a row
    /// with no page. The bar takes it as Return.
    case asReturn
    /// The split already has its most panes: the window says "Cannot Add New Pane".
    case full
    /// An open tab joined the split, or was already a pane of it and is now focused.
    case joined
    /// The row's page opened in a new pane next to the current tab.
    case addedPane
}

extension SidebarStore {
    /// ⌥Return in the command bar: the row opens as a split pane beside `current` instead of in its
    /// place, an open tab of the same space joining the split as it is (the Mac's
    /// MainWindowController.openInSplit, shared with Windows).
    public func openInSplit(_ row: Suggestion?, typed: String, query: String, current: UUID?, window: UUID?,
                            searchURL: @MainActor (String) -> String) -> CommandBarSplitOutcome {
        guard let current, item(current)?.isEmptyTab == false else { return .asReturn }
        if case .switchToTab(let id)? = row?.kind {
            guard id != current, spaceID(ofItem: id) == spaceID(ofItem: current) else { return .asReturn }
            if paneTabIDs(for: current).contains(id) {
                selectTab(id, window: window)
                return .joined
            }
        }
        guard paneTabIDs(for: current).count < splitPaneLimit else { return .full }
        if case .switchToTab(let id)? = row?.kind {
            recordQuerySelection(query: query, url: row?.url ?? "")
            let split = splitContaining(current).map { sp in addToSplit(sp.id, tabID: id, at: nil); return item(sp.id) }
                ?? createSplit(with: [current, id], at: current)
            selectTab(split.flatMap { paneID(for: id, in: $0) } ?? id, window: window)
            return .joined
        }
        guard let url = CommandBarRowPage.url(row: row, typed: typed, query: query, searchURL: searchURL) else { return .asReturn }
        recordQuerySelection(query: query, url: url)
        guard addEmptyPane(nextTo: current, url: url, window: window) != nil else { return .asReturn }
        return .addedPane
    }
}

extension SidebarStore {
    /// Arc's Switch to Split View 1–4 (`splitPaneN`): the `n`th pane of the split the window's tab
    /// is in. False, and nothing changes, outside a split or past its last pane.
    @discardableResult
    public func selectSplitPane(_ n: Int, window: UUID? = nil) -> Bool {
        guard let current = selectedTabID(window: window) else { return false }
        let panes = paneTabIDs(for: current)
        guard panes.count > 1, panes.indices.contains(n - 1) else { return false }
        selectTab(panes[n - 1], window: window)
        return true
    }
}
