import CraCore
import Foundation
import Testing

/// Ctrl-click on a pinned tab's favicon away from its page (Separate From Pinned Tab, #139).
@MainActor
struct PinnedSeparateTests {
    @Test func thePageMovesToANewTodayTabAndThePinnedTabGoesHome() {
        let f = StoreFixture()
        let earlier = f.store.createTab(url: "https://earlier.test/")
        let pinned = f.store.createTab(url: "https://home.test/", pinned: true)
        f.store.updateTab(pinned.id, url: "https://home.test/away", title: "Away")
        f.store.selectTab(pinned.id)

        let result = f.store.separateFromPinnedTab(pinned.id)
        #expect(result?.home == "https://home.test/")
        #expect(f.store.item(pinned.id)?.tab?.url == "https://home.test/")
        let today = result.flatMap { f.store.item($0.today.id) }
        #expect(today?.tab?.url == "https://home.test/away" && today?.tab?.savedTitle == "Away")
        #expect(f.store.isPinned(result?.today.id ?? pinned.id) == false)
        // At the top of Today, and the pinned tab stays the one selected.
        #expect(f.store.item(f.space.todayContainerID)?.children.first == result?.today.id)
        #expect(f.store.item(f.space.todayContainerID)?.children.contains(earlier.id) == true)
        #expect(f.store.selectedTabID == pinned.id)
    }

    @Test func aTabAtHomeOrNotPinnedStaysPut() {
        let f = StoreFixture()
        let pinned = f.store.createTab(url: "https://home.test/", pinned: true)
        let today = f.store.createTab(url: "https://today.test/")
        f.store.updateTab(today.id, url: "https://today.test/next")
        let count = f.store.item(f.space.todayContainerID)?.children.count
        #expect(f.store.separateFromPinnedTab(pinned.id) == nil)
        #expect(f.store.separateFromPinnedTab(today.id) == nil)
        #expect(f.store.item(f.space.todayContainerID)?.children.count == count)
    }
}
