import CraCore
import Testing

/// Arc's + creation menu: its rows in order, New Boost only on a web page, New Split only with room.
struct SidebarCreationEntriesTests {
    @Test
    func arcsRowsInOrder() {
        let rows = SidebarCreationEntries.entries(selectedURL: nil, selectedPanes: nil, paneLimit: 4)
        #expect(rows.map(\.action) == ["newSpace", "newFolder", "newEasel", "newBoost", "addSplitView", "newTab"])
        #expect(rows.map(\.title) == ["New Space", "New Folder", "New Easel", "New Boost", "New Split", "New Tab"])
    }

    @Test
    func boostNeedsAWebPage() {
        func boost(_ url: String?) -> Bool {
            SidebarCreationEntries.entries(selectedURL: url, selectedPanes: 1, paneLimit: 4).first { $0.action == "newBoost" }!.enabled
        }
        #expect(boost("https://example.com/a"))
        #expect(boost("HTTP://example.com"))
        #expect(!boost("about:blank"))
        #expect(!boost("file:///C:/a.txt"))
        #expect(!boost(nil))
    }

    @Test
    func splitNeedsRoomForAPane() {
        func split(_ panes: Int?) -> Bool {
            SidebarCreationEntries.entries(selectedURL: nil, selectedPanes: panes, paneLimit: 4).first { $0.action == "addSplitView" }!.enabled
        }
        #expect(split(1) && split(3))
        #expect(!split(4) && !split(nil))
    }
}
