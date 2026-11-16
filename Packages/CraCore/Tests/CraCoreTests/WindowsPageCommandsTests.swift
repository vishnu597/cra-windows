import CraCore
import Testing

/// Arc's Copy URL as Quote and Stay On Top, which the Windows app runs from the command bar.
struct WindowsPageCommandsTests {
    @Test func quoteAndStayOnTopAreWindowsCommandsWithoutKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for id in ["copyURLQuote", "stayOnTop"] {
            #expect(windows[id]?.shortcuts == [], "\(id)")
            #expect(windows[id]?.inCommandBar == true, "\(id)")
        }
        #expect(windows["copyURLMarkdown"]?.shortcuts.map(\.windowsDisplay) == ["Ctrl+Alt+Shift+C"])
    }

    @Test func copyURLLeavesTrackersOut() {
        #expect(CleanURL.withoutTrackers("https://a.test/p?utm_source=x&id=7&fbclid=y#top") == "https://a.test/p?id=7#top")
    }
}
