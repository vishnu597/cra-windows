import CraCore
import Foundation
import Testing

/// Windows' back and forward list across a relaunch (#273): Cra keeps the addresses and steps
/// through them itself, since stock CEF can't restore a page's navigations.
struct WindowsPageListTests {
    private let t = Date(timeIntervalSince1970: 0)
    private func e(_ s: String) -> PageList.Entry { PageList.Entry(url: "https://\(s).example/") }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func afterARelaunchBackGoesWhereItWent() throws {
        let saved = PageList(entries: [e("a"), e("b"), e("c")], index: 2, savedAt: t)
        #expect(saved.restores(at: "https://c.example/"))
        #expect(!saved.restores(at: "https://x.example/"), "the tab moved on: it starts fresh")
        let back = try #require(saved.back(pageCanGoBack: false))
        #expect(back.url == "https://b.example/")
        #expect(saved.back(pageCanGoBack: true) == nil, "the page's own pages first")
        let forward = try #require(back.list.forward(pageCanGoForward: false, pageEntries: 1))
        #expect(forward.url == "https://c.example/")
        #expect(back.list.forward(pageCanGoForward: false, pageEntries: 2) == nil, "it went on to another page")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/273"))
    func theSavedListFollowsThePage() {
        let started = PageList(entries: [e("a"), e("b"), e("c")], index: 1, savedAt: t)
        // Still on its one entry: the pages ahead stay.
        let same = started.merged(live: [e("b2")], liveIndex: 0, savedAt: t)
        #expect(same.entries == [e("a"), e("b2"), e("c")] && same.index == 1)
        // Went on to a link: the pages ahead go, the ones behind stay.
        let on = started.merged(live: [e("b"), e("d")], liveIndex: 1, savedAt: t)
        #expect(on.entries == [e("a"), e("b"), e("d")] && on.index == 2)
        // A fresh page: its own list.
        let fresh = PageList.fresh(live: [e("x"), e("y")], liveIndex: 1, savedAt: t)
        #expect(fresh.entries == [e("x"), e("y")] && fresh.index == 1)
    }

    @Test func sixPagesAreKeptOnEachSide() {
        let live = (0..<20).map { e("p\($0)") }
        let list = PageList.fresh(live: live, liveIndex: 10, savedAt: t)
        #expect(list.entries.count == 13 && list.index == 6 && list.current == e("p10"))
    }

    @Test func navigationHistoryRepliesAreRead() throws {
        let json = #"{"currentIndex":1,"entries":[{"id":3,"url":"https://a.example/","title":"A"},{"id":4,"url":"https://b.example/","title":"B"}]}"#
        let live = try #require(PageList.live(history: json))
        #expect(live.index == 1 && live.entries.map(\.title) == ["A", "B"])
        #expect(PageList.live(history: "{}") == nil)
        #expect(PageList.replaceScript("https://a.example/\"x") == #"location.replace(["https://a.example/\"x"][0])"#)
    }

    @Test func chromiumsOwnPagesStartFresh() {
        let saved = PageList(entries: [PageList.Entry(url: "https://a.example/"), PageList.Entry(url: "chrome://settings/")], index: 1, savedAt: t)
        #expect(!saved.restores(at: "chrome://settings/"))
    }
}
