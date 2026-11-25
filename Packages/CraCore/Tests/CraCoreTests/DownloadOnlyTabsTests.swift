import CraCore
import Testing

/// A tab whose page only downloaded closes, as Chrome's does, and its page waits out of sight
/// for its downloads (PC test, 25 Nov 2026: the blank tab kept the keys and took the next address).
struct DownloadOnlyTabsTests {
    @Test func aTabThatOnlyDownloadedClosesAndItsPageWaitsForTheDownload() {
        var tabs = DownloadOnlyTabs<Int>()
        #expect(tabs.report(7, from: 1, first: true, pageHasDocument: false, running: true) == .holdAndCloseTab)
        #expect(tabs.held == [1: [7]])
        // Progress: still held.
        #expect(tabs.report(7, from: 1, first: false, pageHasDocument: false, running: true) == .none)
        // A second download from the held page (a redirect chain's next file) is waited for too.
        #expect(tabs.report(8, from: 1, first: true, pageHasDocument: false, running: true) == .none)
        #expect(tabs.report(7, from: 1, first: false, pageHasDocument: false, running: false) == .none)
        #expect(tabs.report(8, from: 1, first: false, pageHasDocument: false, running: false) == .closePage)
        #expect(tabs.held.isEmpty)
    }

    @Test func aPageThatShowsSomethingKeepsItsTab() {
        var tabs = DownloadOnlyTabs<Int>()
        // A link on a page, or an address typed over a page: the page stays, as in Chrome.
        #expect(tabs.report(1, from: 1, first: true, pageHasDocument: true, running: true) == .none)
        // Only the first report decides: a later one for a known download changes nothing.
        #expect(tabs.report(2, from: 2, first: false, pageHasDocument: false, running: true) == .none)
        #expect(tabs.held.isEmpty)
    }

    @Test func aDownloadThatEndedAtOnceClosesTheTabWithItsPage() {
        var tabs = DownloadOnlyTabs<Int>()
        // Refused, or its Save As dialog cancelled: nothing to wait for.
        #expect(tabs.report(3, from: 3, first: true, pageHasDocument: false, running: false) == .closeTab)
        #expect(tabs.held.isEmpty)
    }

    @Test func aClosedPageIsForgotten() {
        var tabs = DownloadOnlyTabs<Int>()
        _ = tabs.report(7, from: 1, first: true, pageHasDocument: false, running: true)
        tabs.forget(1)
        #expect(tabs.held.isEmpty)
        #expect(tabs.report(7, from: 1, first: false, pageHasDocument: false, running: false) == .none)
    }
}
