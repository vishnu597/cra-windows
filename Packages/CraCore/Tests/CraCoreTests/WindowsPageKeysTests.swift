import CraCore
import Testing

/// Ctrl+PgUp / Ctrl+PgDn go up and down the sidebar on Windows, now that Ctrl+Tab is Arc's
/// recent-tab switcher.
struct WindowsPageKeysTests {
    @Test func pageKeysReadWriteAndShow() {
        let down = KeyChord(windowsVirtualKey: 0x22, control: true, shift: false, alt: false)
        let up = KeyChord(windowsVirtualKey: 0x21, control: true, shift: false, alt: false)
        #expect(down == KeyChord(KeyChord.pageDown, .control) && up == KeyChord(KeyChord.pageUp, .control))
        #expect(down?.windowsDisplay == "Ctrl+PgDn" && up?.windowsDisplay == "Ctrl+PgUp")
        #expect(KeyChord.recorded(windowsVirtualKey: 0x22, control: false, shift: false, alt: false) == KeyChord(KeyChord.pageDown, []))
    }

    @Test func ctrlTabIsTheSwitcherOnWindows() {
        let keys = KeyBindingDefaults.windowsShortcuts
        #expect(keys["recentTab"] == [KeyChord(KeyChord.tab, .control)])
        #expect(keys["recentTabBackward"] == [KeyChord(KeyChord.tab, [.control, .shift])])
        #expect(keys["nextTab"] == [KeyChord(KeyChord.pageDown, .control)])
        #expect(keys["previousTab"] == [KeyChord(KeyChord.pageUp, .control)])
    }
}
