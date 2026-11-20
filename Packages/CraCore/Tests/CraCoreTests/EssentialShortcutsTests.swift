import CraCore
import Foundation
import Testing

/// Arc's Essential Keyboard Shortcuts card, the Mac's and Windows' (CraCore EssentialShortcuts).
struct EssentialShortcutsTests {
    @Test func arcsFiveRowsAreCommands() {
        #expect(EssentialShortcuts.rows.map(\.action) == ["newTab", "recentTab", "copyURL", "addSplitView", "newLittleWindow"])
        let mac = Set(KeyBindingDefaults.mac.map(\.id))
        for row in EssentialShortcuts.rows { #expect(mac.contains(row.action), "\(row.action)") }
        #expect(EssentialShortcuts.width == 475 && EssentialShortcuts.height == 462)
    }

    /// Windows' card draws a cap per key of each row's Windows shortcut, and the command bar offers it.
    @Test func windowsDrawsItsOwnKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["newTab"]?.primary?.windowsCaps == ["Ctrl", "T"])
        #expect(windows["recentTab"]?.primary?.windowsCaps == ["Ctrl", "Tab"])
        #expect(KeyChord("t", [.control, .shift]).windowsCaps == ["Ctrl", "Shift", "T"])
        #expect(windows["essentialShortcuts"]?.inCommandBar == true)
        #expect(windows["essentialShortcuts"]?.shortcuts == [])
    }
}
