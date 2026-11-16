import CraCore
import Testing

struct TabSoundTests {
    @Test func aPlayingOrMutedTabShowsItsSpeaker() {
        #expect(TabSound.button(muted: false, audible: false) == nil)
        #expect(TabSound.button(muted: false, audible: true) == .playing)
        #expect(TabSound.button(muted: true, audible: false) == .muted, "a muted tab shows it while quiet")
        #expect(TabSound.button(muted: true, audible: true) == .muted)
        #expect(TabSound.button(muted: true, audible: true, editing: true) == nil, "not while the name is edited")
    }

    @Test func itsGlyphAndHelpSayWhatAClickDoes() {
        #expect(TabSound.playing.symbol == "speaker.wave.3" && TabSound.playing.help == "Mute Tab")
        #expect(TabSound.muted.symbol == "speaker.slash" && TabSound.muted.help == "Unmute Tab")
        #expect(TabSound.menuTitle(muted: false) == "Mute" && TabSound.menuTitle(muted: true) == "Unmute")
    }

    @Test func muteIsAWindowsCommandWithoutAKey() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["muteTab"]?.shortcuts == [])
        #expect(windows["muteTab"]?.inCommandBar == true)
    }
}
