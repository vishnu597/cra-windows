import CraCore
import Testing

/// The toolbar's address and which bar a window's strip shows (the Windows toolbar).
struct ToolbarAddressTests {
    @Test func showsTheHostUnlessFullURLIsOn() {
        let host = ToolbarAddress.parts(url: "https://www.example.com/docs/page?q=1", showFullURL: false)
        #expect(host.host == "example.com" && host.path == "")
        let full = ToolbarAddress.parts(url: "https://www.example.com/docs/page?q=1", showFullURL: true)
        #expect(full.host == "example.com" && full.path == "/docs/page?q=1")
    }

    @Test func anAddressWithNoHostShowsAsTyped() {
        let parts = ToolbarAddress.parts(url: "about:blank", showFullURL: false)
        #expect(parts.host == "about:blank" && parts.path == "")
    }

    @Test func developerModeWinsAndSplitsShowNoBar() {
        #expect(WindowTopBar.resolve(showToolbar: false, developerMode: false, paneCount: 1, hasURL: true) == .none)
        #expect(WindowTopBar.resolve(showToolbar: true, developerMode: false, paneCount: 1, hasURL: true) == .toolbar)
        #expect(WindowTopBar.resolve(showToolbar: true, developerMode: true, paneCount: 1, hasURL: true) == .developer)
        #expect(WindowTopBar.resolve(showToolbar: false, developerMode: true, paneCount: 1, hasURL: true) == .developer)
        #expect(WindowTopBar.resolve(showToolbar: true, developerMode: true, paneCount: 2, hasURL: true) == .none)
        // A window with no tab still shows the toolbar (its buttons disabled), not the developer bar.
        #expect(WindowTopBar.resolve(showToolbar: true, developerMode: true, paneCount: 0, hasURL: false) == .toolbar)
    }

    @Test func toolbarCommandsRunOnWindows() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["toggleToolbar"]?.inCommandBar == true)
        #expect(windows["toggleToolbar"]?.name == "Toggle Toolbar")
        #expect(windows["stop"] != nil)
    }

    /// The address's menu is the Mac's, and every command in it runs on Windows.
    @Test func addressMenuIsTheMacsAndRunsOnWindows() {
        let rows = ToolbarAddressMenu.rows(showFullURL: false, autoHide: true)
        #expect(rows == [.command("copyURL", "Copy URL"), .command("capturePage", "Capture…"),
                         .command("captureFullPage", "Capture Full Page"), .separator,
                         .command("manageExtensions", "Manage Extensions…"), .separator,
                         .fullURL(showing: false), .autoHide(on: true), .command("toggleToolbar", "Hide Toolbar")])
        #expect(!ToolbarAddressMenu.rows(showFullURL: true, autoHide: false, panes: 2).contains(.autoHide(on: false)),
                "a split pane's bar never hides")
        #expect(ToolbarAddressMenu.rows(showFullURL: true, autoHide: false).contains(.fullURL(showing: true)))
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for case .command(let id, _) in rows { #expect(windows[id] != nil, "\(id) runs on Windows") }
        #expect(windows["captureFullPage"]?.inCommandBar == true)
    }

    /// Edit ▸ Paste and Go (#610) runs on Windows from the command bar, with no key: the Mac's ⌥⌘V
    /// would be Ctrl+Alt+V, AltGr+V on many keyboards.
    @Test
    func pasteAndGoIsAWindowsCommand() {
        let paste = KeyBindingDefaults.windows.first { $0.id == "pasteAndGo" }
        #expect(paste?.inCommandBar == true)
        #expect(paste?.shortcuts == [])
        #expect(paste?.name == "Paste and Go")
    }
}

/// The reload menu's rows, all of them commands Windows runs.
struct ReloadMenuItemsTests {
    @Test func groupsAreTheMacsAndRunOnWindows() {
        #expect(ReloadMenuItems.groups == [["reload", "hardReload"], ["clearCookies", "clearCache"], ["viewSource", "devTools"]])
        let windows = Set(KeyBindingDefaults.windows.map(\.id))
        for id in ReloadMenuItems.groups.joined() { #expect(windows.contains(id), "\(id)") }
    }
}
