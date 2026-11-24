import CraCore
import Foundation
import Testing

/// Arc's split menu: Rename…, and Reset Name and Icon back to the panes' names (SidebarMenus.split).
@MainActor
struct SplitRenameTests {
    @Test func aSplitRowShowsItsNameOrItsPanes() throws {
        let f = StoreFixture()
        let left = f.store.createTab(url: "https://left.example/", title: "Left")
        let right = f.store.createTab(url: "https://right.example/", title: "Right")
        let split = try #require(f.store.createSplit(with: [left.id, right.id], inPlace: true))
        #expect(f.store.splitRowTitle(split.id) == "Left | Right")
        #expect(!f.store.splitHasOwnNameOrIcon(split.id))

        f.store.rename(split.id, to: "  Research ")
        #expect(f.store.splitRowTitle(split.id) == "Research")
        #expect(f.store.splitHasOwnNameOrIcon(split.id))
        #expect(!f.store.splitHasOwnNameOrIcon(left.id), "a tab is no split")

        f.store.resetSplitNameAndIcon(split.id)
        #expect(f.store.splitRowTitle(split.id) == "Left | Right")
        #expect(!f.store.splitHasOwnNameOrIcon(split.id))

        f.store.rename(split.id, to: "")
        #expect(f.store.splitRowTitle(split.id) == "Left | Right", "an empty name is no name")
    }
}
