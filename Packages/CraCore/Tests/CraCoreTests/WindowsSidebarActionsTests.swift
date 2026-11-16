import CraCore
import Testing

/// The sidebar's New Folder, New Space and Clear Today and the Library's archive commands, which
/// the Windows app runs from the command bar (Clear Today also from Ctrl+Shift+K).
struct WindowsSidebarActionsTests {
    let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })

    @Test func sidebarAndArchiveCommandsAreInTheCommandBar() {
        for id in ["newFolder", "newSpace", "clearToday", "showArchive", "clearArchive"] {
            #expect(windows[id]?.inCommandBar == true, "\(id)")
        }
        for id in ["newFolder", "newSpace", "showArchive", "clearArchive"] {
            #expect(windows[id]?.shortcuts == [], "\(id)")
        }
    }

    @Test func clearTodayKeepsTheMacsKey() {
        #expect(windows["clearToday"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+Shift+K"])
        let others = KeyBindingDefaults.windows.filter { $0.id != "clearToday" && $0.shortcuts.contains(KeyChord("k", [.control, .shift])) }
        #expect(others.isEmpty)
    }
}
