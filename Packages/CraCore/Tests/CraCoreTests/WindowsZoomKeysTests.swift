import CraCore
import Testing

/// Zoom, Print and View Source take Chrome for Windows' keys, so Cra runs them (they're in its
/// key table, the command bar and Settings ▸ Shortcuts) rather than leaving them to Chromium.
struct WindowsZoomKeysTests {
    @Test func pageCommandsHaveChromesKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["zoomIn"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+="])
        #expect(windows["zoomOut"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+-"])
        #expect(windows["resetZoom"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+0"])
        #expect(windows["print"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+P"])
        #expect(windows["viewSource"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+U"])
        for id in ["zoomIn", "zoomOut", "resetZoom", "print", "viewSource"] {
            #expect(windows[id]?.inCommandBar == true, "\(id)")
        }
    }

    @Test func zoomInLeavesCtrlShiftEqualsToSplitView() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["addSplitView"]?.primary?.windowsDisplay == "Ctrl+Shift+=")
        let ctrlShiftEquals = KeyBindingDefaults.windows.filter { $0.shortcuts.contains(KeyChord("=", [.control, .shift])) }
        #expect(ctrlShiftEquals.map(\.id) == ["addSplitView"])
    }

    @Test func zoomKeysMapToTheirVirtualKeys() {
        #expect(KeyChord("=", .control).windowsVirtualKey == 0xBB)
        #expect(KeyChord("-", .control).windowsVirtualKey == 0xBD)
        #expect(KeyChord("0", .control).windowsVirtualKey == 0x30)
        #expect(KeyChord(windowsVirtualKey: 0xBB, control: true, shift: false, alt: false) == KeyChord("=", .control))
    }
}
