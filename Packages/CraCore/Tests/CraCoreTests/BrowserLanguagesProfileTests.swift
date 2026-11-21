import CraCore
import Foundation
import Testing

/// Settings ▸ Profiles ▸ Website languages on Windows: which space Change… opens the page in, and
/// where a profile's languages are read from.
struct BrowserLanguagesProfileTests {
    @Test func opensInTheFocusedSpaceWhenItIsOnTheProfile() {
        let focused = UUID(), other = UUID()
        #expect(BrowserLanguages.space(focused: focused, onProfile: [other, focused]) == focused)
        #expect(BrowserLanguages.space(focused: focused, onProfile: [other]) == other, "else the profile's first space")
        #expect(BrowserLanguages.space(focused: focused, onProfile: []) == nil, "no space on it: the button is off")
    }

    @Test func readsChromiumsLiveValueBeforeTheFile() {
        let file = Data(#"{"intl":{"accept_languages":"da,en"}}"#.utf8)
        var fileRead = false
        let live = BrowserLanguages.codes(livePref: "\"de,en-GB\"") { fileRead = true; return file }
        #expect(live == ["de", "en-GB"])
        #expect(!fileRead, "a loaded profile's live value wins")
        #expect(BrowserLanguages.codes(livePref: nil) { file } == ["da", "en"])
        #expect(BrowserLanguages.codes(livePref: nil) { nil } == [], "a profile never opened: Chromium's defaults")
    }
}
