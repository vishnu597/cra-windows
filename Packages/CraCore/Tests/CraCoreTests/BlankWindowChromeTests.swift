import CraCore
import Foundation
import Testing

/// A Blank Window on Windows shows and runs what the Mac's does (#220).
struct BlankWindowChromeTests {
    @Test func sidebarIsItsTabsOnly() {
        let blank = BlankWindowChrome.sidebar(blank: true)
        #expect(!blank.favorites && !blank.pinned && !blank.divider && !blank.spaceDock && !blank.plus && !blank.headerActs)
        #expect(blank.moveTo)
        let normal = BlankWindowChrome.sidebar(blank: false)
        #expect(normal.favorites && normal.pinned && normal.divider && normal.spaceDock && normal.plus && normal.headerActs)
        #expect(!normal.moveTo)
    }

    @Test func spaceCommandsAreOffInABlankWindow() {
        for id in ["editSpace", "deleteSpace", "nextSpace", "manageSpaces", "pinTab", "favoriteTab", "newFolder", "collapsePinned"] {
            #expect(!BlankWindowChrome.runs(id, blank: true), "\(id)")
            #expect(BlankWindowChrome.runs(id, blank: false), "\(id)")
        }
        #expect(BlankWindowChrome.runs("newTab", blank: true))
        #expect(BlankWindowChrome.runs("closeTab", blank: true))
    }

    @Test func blankWindowIsAWindowsCommand() {
        let blank = KeyBindingDefaults.windows.first { $0.id == "newBlankWindow" }
        #expect(blank?.inCommandBar == true)
        #expect(blank?.shortcuts == [], "the Mac's ⌃⌘N has no Windows key; Ctrl+Alt+N is New Little Window")
        #expect(blank?.name == "Blank Window")
    }

    @Test @MainActor func moveToListsTheSidebarsSpaces() {
        let f = StoreFixture()
        let w = f.store.addBlankWindow(frame: nil)
        let own = f.store.focusedSpaceID(window: w.id)
        let all = f.store.orderedSpaces + [f.store.focusedSpace(window: w.id)]
        let targets = BlankWindowChrome.moveTargets(all) { f.store.isStandalone(space: $0) }
        #expect(targets.map(\.id) == f.store.orderedSpaces.map(\.id))
        #expect(!targets.contains { $0.id == own })
    }

    /// What the Windows app leans on: a Blank Window has its own "This Window" space, outside the
    /// space list, which goes with the window.
    @Test @MainActor func storeOpensAndClosesABlankWindow() {
        let f = StoreFixture()
        let w = f.store.addBlankWindow(frame: nil)
        #expect(f.store.isBlank(window: w.id) && f.store.isStandalone(window: w.id))
        #expect(f.store.focusedSpace(window: w.id).title == BlankWindow.title)
        #expect(f.store.pagedSpaces(window: w.id).count == 1)
        let own = f.store.focusedSpaceID(window: w.id)
        #expect(!f.store.spaceOrder.contains(own))
        f.store.removeWindow(w.id)
        #expect(f.store.space(own) == nil, "closing the window removes its space")
        #expect(f.sound)
    }
}
