import Foundation

extension SidebarStore {
    /// Arc's ⌘-click (Ctrl-click on Windows) on the favicon of a pinned tab away from its page,
    /// "Separate From Pinned Tab" (GitHub #139): the page it is on moves to a new Today tab at
    /// the top of the tab's space, left unselected, and the pinned tab goes back to its pinned
    /// page. Answers the new Today tab and the pinned URL for the pinned tab's page to load; nil
    /// for a tab that isn't pinned or is already at home. (The Mac's
    /// MainWindowController.separatePinnedTab does the same steps.)
    public func separateFromPinnedTab(_ id: UUID) -> (today: SidebarItem, home: String)? {
        guard let t = item(id)?.tab, isPinned(id), t.url != t.savedURL else { return nil }
        let today = createTab(url: t.url, title: t.savedTitle, in: spaceID(ofItem: id), select: false, index: 0)
        guard let home = resetPinnedTab(id) else { return nil }
        return (today, home)
    }
}
