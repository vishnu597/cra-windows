import CraCore
import Foundation
import Testing

/// Restore Last Closed Tab as Windows' BrowserWindow calls it: a pinned tab closed with
/// `closePinnedTab` (its window shows `closeSuccessor`), then `reopenLastClosed(in:peek:)` with the
/// window's closed Peek, newest first across pinned tabs, archived tabs and the Peek.
@MainActor
struct RestoreLastClosedTests {
    @Test func pinnedArchivedAndPeekComeBackNewestFirst() {
        let f = StoreFixture()
        let window: UUID = f.store.prefs.windows.first?.id ?? f.store.addWindow(spaceID: f.space.id, frame: nil).id
        f.store.clearArchive()
        let home = f.store.createTab(url: "https://a.test/home", pinned: true, select: false)
        let today = f.store.createTab(url: "https://b.test/")
        f.store.archiveTab(today.id, reason: .manual)
        f.clock.advance(by: 60)

        // A closed Peek, then the open pinned tab closed while away from its pinned page.
        let peek = ReopenClosedTab.ClosedPeek(url: "https://peek.test/", tabID: home.id, closedAt: f.clock.now)
        f.clock.advance(by: 60)
        f.store.selectTab(home.id, window: window)
        f.store.updateTab(home.id, url: "https://a.test/deep", title: "Deep")
        let unloaded = f.store.closePinnedTab(home.id, wasOpen: true)
        #expect(unloaded == [home.id])
        #expect(f.store.item(home.id)?.tab?.url == "https://a.test/home")
        f.store.selectTab(f.store.closeSuccessor(ofPinned: home.id, window: window), window: window)

        // Newest first: the pinned tab at the page it was on, then the Peek, then the archived tab.
        let first = f.store.reopenLastClosed(in: window, peek: peek)
        #expect(first?.tabID == home.id)
        #expect(f.store.item(home.id)?.tab?.url == "https://a.test/deep")
        #expect(f.store.selectedTabID(window: window) == home.id)
        #expect(f.store.reopenLastClosed(in: window, peek: peek) == .peek(url: "https://peek.test/", tabID: home.id))
        #expect(f.store.reopenLastClosed(in: window, peek: nil) == .archived(today.id))
        #expect(f.store.reopenLastClosed(in: window, peek: nil) == nil)
        #expect(f.sound)
    }

    @Test func aPinnedTabClosedInTheBackgroundLeavesNothing() {
        let f = StoreFixture()
        let window: UUID = f.store.prefs.windows.first?.id ?? f.store.addWindow(spaceID: f.space.id, frame: nil).id
        f.store.clearArchive()
        let home = f.store.createTab(url: "https://a.test/home", pinned: true, select: false)
        f.store.updateTab(home.id, url: "https://a.test/elsewhere")
        f.store.closePinnedTab(home.id, wasOpen: false)
        #expect(f.store.item(home.id)?.tab?.url == "https://a.test/home")
        #expect(f.store.reopenLastClosed(in: window, peek: nil) == nil)
    }
}
