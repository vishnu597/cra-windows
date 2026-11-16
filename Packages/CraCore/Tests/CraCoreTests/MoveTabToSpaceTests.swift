import CraCore
import Foundation
import Testing

/// Move Tab to Space N (#86): the open tab goes to the space and the window follows it.
@MainActor
struct MoveTabToSpaceTests {
    @Test func theOpenTabMovesAndTheWindowFollows() {
        let f = StoreFixture()
        let tab = f.store.createTab(url: "https://a.test/")
        let work = f.store.createSpace(title: "Work", emoji: "💼", focus: false)
        #expect(f.store.moveTabAndFollow(tab.id, toSpace: work.id))
        #expect(f.store.spaceID(ofItem: tab.id) == work.id)
        #expect(f.store.focusedSpaceID == work.id)
        #expect(f.store.selectedTabID == tab.id)
        #expect(!f.store.moveTabAndFollow(tab.id, toSpace: work.id), "already there")
    }

    @Test func windowsKeysAddShiftToGoToSpace() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for n in 1...9 {
            #expect(windows["moveTabToSpace\(n)"]?.shortcuts.map(\.windowsDisplay) == ["Alt+Shift+\(n)"])
            #expect(windows["space\(n)"]?.shortcuts.map(\.windowsDisplay) == ["Alt+\(n)"])
        }
    }
}
