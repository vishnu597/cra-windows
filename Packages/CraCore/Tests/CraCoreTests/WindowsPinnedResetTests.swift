import CraCore
import Testing

/// Back to Pinned Page and Reset all tabs in this Space, which the Windows app runs from the
/// command bar and the tab menu.
struct WindowsPinnedResetTests {
    @Test func resetCommandsAreWindowsCommandsWithoutKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for id in ["resetTab", "resetSpaceTabs"] {
            #expect(windows[id]?.shortcuts == [], "\(id)")
            #expect(windows[id]?.inCommandBar == true, "\(id)")
        }
    }

    @Test func goingHomeBringsBackThePinnedPagesName() {
        var tab = TabData(url: "https://home.example/", title: "Home")
        tab.noteTitle("Home", pinned: true)
        tab.url = "https://elsewhere.example/page"
        tab.noteTitle("Elsewhere", pinned: true)
        tab.returnHome()
        #expect(tab.url == "https://home.example/")
        #expect(tab.savedTitle == "Home")
    }
}
