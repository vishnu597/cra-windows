import CraCore
import Foundation
import Testing

/// ⌥Return in the command bar (Alt+Return on Windows): the row opens in Split View beside the
/// current tab (SidebarStore.openInSplit), and the page a row opens anew (CommandBarRowPage), shared
/// by the Mac's MainWindowController and Windows' BrowserWindow.
@MainActor
struct CommandBarSplitTests {
    private let search: @MainActor (String) -> String = { "https://search.example/?q=\($0)" }

    private func row(_ kind: SuggestionKind, url: String?) -> Suggestion {
        Suggestion(id: "r", kind: kind, title: "Row", subtitle: "", url: url, faviconKey: nil, symbol: nil, trailing: nil, score: 0)
    }

    @Test func rowPagesFollowWhatReturnOpens() {
        #expect(CommandBarRowPage.url(row: nil, typed: "cats", query: "cats", searchURL: search) == "https://search.example/?q=cats")
        #expect(CommandBarRowPage.url(row: nil, typed: "example.com", query: "example.com", searchURL: search) == "https://example.com")
        #expect(CommandBarRowPage.url(row: nil, typed: "", query: "", searchURL: search) == nil)
        #expect(CommandBarRowPage.url(row: row(.history, url: "https://h.example"), typed: "h", query: "h", searchURL: search) == "https://h.example")
        #expect(CommandBarRowPage.url(row: row(.search, url: nil), typed: "dogs", query: "dogs", searchURL: search) == "https://search.example/?q=dogs")
        #expect(CommandBarRowPage.url(row: row(.command("find"), url: nil), typed: "find", query: "find", searchURL: search) == nil,
                "a command opens no page")
        #expect(CommandBarRowPage.url(row: row(.switchSpace(UUID()), url: nil), typed: "w", query: "w", searchURL: search) == nil)
    }

    @Test func aTypedSearchOpensInANewPaneBesideTheTab() throws {
        let f = StoreFixture()
        let current = f.store.createTab(url: "https://current.example", select: true)
        let outcome = f.store.openInSplit(nil, typed: "cats", query: "cats", current: current.id, window: nil, searchURL: search)
        #expect(outcome == .addedPane)
        let split = try #require(f.store.splitContaining(current.id))
        #expect(split.children.count == 2)
        #expect(split.children.first == current.id, "the new pane comes after the current tab")
        let pane = try #require(f.store.item(split.children[1]))
        #expect(pane.tab?.url == "https://search.example/?q=cats")
        #expect(f.store.selectedTabID == pane.id)
    }

    @Test func anOpenTabOfTheSpaceJoinsTheSplitAsItIs() throws {
        let f = StoreFixture()
        let other = f.store.createTab(url: "https://other.example", select: false)
        let current = f.store.createTab(url: "https://current.example", select: true)
        let outcome = f.store.openInSplit(row(.switchToTab(other.id), url: "https://other.example"), typed: "other", query: "other",
                                          current: current.id, window: nil, searchURL: search)
        #expect(outcome == .joined)
        let split = try #require(f.store.splitContaining(current.id))
        #expect(split.children.contains(other.id))
        #expect(f.store.selectedTabID == other.id)
        // Picking it again focuses the pane it already is.
        f.store.selectTab(current.id)
        #expect(f.store.openInSplit(row(.switchToTab(other.id), url: nil), typed: "o", query: "o", current: current.id, window: nil,
                                    searchURL: search) == .joined)
        #expect(f.store.selectedTabID == other.id)
    }

    @Test func noSplitToMakeIsReturn() {
        let f = StoreFixture()
        #expect(f.store.openInSplit(nil, typed: "cats", query: "cats", current: nil, window: nil, searchURL: search) == .asReturn,
                "no tab")
        let empty = f.store.createTab(url: "", select: true)
        #expect(f.store.openInSplit(nil, typed: "cats", query: "cats", current: empty.id, window: nil, searchURL: search) == .asReturn,
                "an empty tab takes the row itself")
        let current = f.store.createTab(url: "https://current.example", select: true)
        #expect(f.store.openInSplit(row(.command("find"), url: nil), typed: "find", query: "find", current: current.id, window: nil,
                                    searchURL: search) == .asReturn, "a command opens no page")
        #expect(f.store.openInSplit(row(.switchToTab(current.id), url: nil), typed: "c", query: "c", current: current.id, window: nil,
                                    searchURL: search) == .asReturn, "the current tab itself")
        #expect(f.store.splitContaining(current.id) == nil)
    }

    @Test func aFullSplitTakesNoMorePanes() throws {
        let f = StoreFixture()
        let current = f.store.createTab(url: "https://current.example", select: true)
        for i in 1..<f.store.splitPaneLimit {
            #expect(f.store.openInSplit(nil, typed: "q\(i)", query: "q\(i)", current: current.id, window: nil, searchURL: search) == .addedPane)
        }
        #expect(f.store.openInSplit(nil, typed: "more", query: "more", current: current.id, window: nil, searchURL: search) == .full)
        #expect(try #require(f.store.splitContaining(current.id)).children.count == f.store.splitPaneLimit)
    }

    @Test func switchToSplitViewNPicksThatPane() throws {
        let f = StoreFixture()
        let a = f.store.createTab(url: "https://a.example", select: true)
        #expect(!f.store.selectSplitPane(1), "no split")
        let b = f.store.createTab(url: "https://b.example", select: false)
        let c = f.store.createTab(url: "https://c.example", select: false)
        _ = try #require(f.store.createSplit(with: [a.id, b.id, c.id], at: a.id))
        f.store.selectTab(a.id)
        #expect(f.store.selectSplitPane(3))
        let panes = f.store.paneTabIDs(for: a.id)
        #expect(f.store.selectedTabID == panes[2])
        #expect(!f.store.selectSplitPane(4), "past the last pane")
        #expect(f.store.selectedTabID == panes[2])
        #expect(f.store.selectSplitPane(1))
        #expect(f.store.selectedTabID == panes[0])
        #expect(KeyBindingDefaults.windowsShortcuts["splitPane2"] == [], "Windows performs it, with no default keys")
    }
}
