import CraCore
import Foundation
import Testing

/// Rename Space… and Rename… on a tab or folder, as the sidebar commits what was typed.
@MainActor
struct SidebarRenameTests {
    @Test func aSpaceTakesATrimmedName() {
        let f = StoreFixture()
        #expect(f.store.renameSpace(f.space.id, to: "  Work \n"))
        #expect(f.store.space(f.space.id)?.title == "Work")
        #expect(f.reopened().store.space(f.space.id)?.title == "Work", "the name is saved")
    }

    @Test func anEmptyOrSameNameKeepsTheSpacesName() {
        let f = StoreFixture()
        let before = f.store.space(f.space.id)?.title
        #expect(!f.store.renameSpace(f.space.id, to: "   "))
        #expect(!f.store.renameSpace(f.space.id, to: before ?? ""))
        #expect(!f.store.renameSpace(UUID(), to: "Gone"), "no such space")
        #expect(f.store.space(f.space.id)?.title == before)
    }

    @Test func aTabsNameOfItsOwnGoesWhenClearedAgain() {
        let f = StoreFixture()
        let tab = f.store.createTab(url: "https://a.test/", title: "Page title")
        f.store.rename(tab.id, to: " Mine ")
        #expect(f.store.item(tab.id)?.displayTitle == "Mine")
        f.store.rename(tab.id, to: "")
        #expect(f.store.item(tab.id)?.displayTitle == "Page title", "back to the page's own title")
    }
}

/// The Windows app performs the sidebar's row commands, so they're in its key table, the command
/// bar and Settings ▸ Shortcuts.
struct SidebarRowCommandsTests {
    @Test func renameDuplicateAndFavoriteAreWindowsCommands() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for id in ["renameTab", "duplicateTab", "favoriteTab"] {
            #expect(windows[id] != nil, "\(id)")
            #expect(windows[id]?.shortcuts.isEmpty == true, "\(id) has no key, as on the Mac")
        }
    }
}

/// Split View's commands the Windows app performs: Expand Current Split in the command bar, and
/// Switch to Split View 1–4 with no default keys (Ctrl+Shift+2 is Capture on Windows).
struct WindowsSplitCommandsTests {
    @Test func expandAndSwitchToPaneAreInTheWindowsTable() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["expandSplitPane"]?.shortcuts == [])
        #expect(windows["expandSplitPane"]?.inCommandBar == true)
        for n in 1...4 { #expect(windows["splitPane\(n)"]?.shortcuts == [], "splitPane\(n)") }
        #expect(windows["capturePage"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+Shift+2"])
    }
}

/// Arc's sidebar commands the Windows command bar runs (the store does the work), without keys.
struct WindowsSidebarCommandsTests {
    @Test func theyAreInTheWindowsTableWithoutKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for id in ["collapsePinned", "revealTab", "collapseAllFolders", "expandAllFolders"] {
            #expect(windows[id]?.shortcuts == [], "\(id)")
            #expect(windows[id]?.inCommandBar == true, "\(id)")
        }
    }
}
