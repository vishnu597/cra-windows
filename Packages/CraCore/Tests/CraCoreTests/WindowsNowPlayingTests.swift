import CraCore
import Foundation
import Testing

/// Arc's now-playing player in the sidebar on Windows (#33), where stock CEF reports neither the
/// audible state nor the media session: the cards follow what each page's script says.
struct WindowsNowPlayingTests {
    private let a = UUID(), b = UUID()
    private let music = AudibleProbe.Answer(audible: true, controllable: true)
    private let quiet = AudibleProbe.Answer(audible: false)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/33")) func aTabThatStartsPlayingGetsACardOldestFirst() {
        var list = NowPlayingList()
        list.heard(a, music)
        list.heard(b, .init(audible: true, controllable: true, video: true))
        #expect(list.entries == [.init(id: a, playing: true), .init(id: b, playing: true, hasVideo: true)])
        list.heard(a, music)
        #expect(list.entries.map(\.id) == [a, b], "a card is made once")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/411")) func aDingMakesNoCard() {
        var list = NowPlayingList()
        list.heard(a, .init(audible: true, controllable: false))
        #expect(list.entries.isEmpty)
        list.heard(a, quiet)
        #expect(list.entries.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/33")) func aPausedTabKeepsItsCardTillItNavigatesQuiet() {
        var list = NowPlayingList()
        list.heard(a, music)
        list.heard(a, quiet)
        #expect(list.entries == [.init(id: a, playing: false)], "paused, still listed")
        list.heard(a, .init(audible: true, controllable: false))
        #expect(list.entries == [.init(id: a, playing: true)], "playing again shows playing")
        list.navigated(a, audible: true)
        #expect(list.entries.count == 1, "a playlist moving on keeps its card")
        list.navigated(a, audible: false)
        #expect(list.entries.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/33")) func dismissedClosedAndOnScreenTabsShowNoCard() {
        var list = NowPlayingList()
        list.heard(a, music)
        list.heard(b, music)
        #expect(list.shown(onScreen: [b]).map(\.id) == [a], "the tab on screen has no card")
        list.keep(only: [b])
        #expect(list.entries.map(\.id) == [b], "a closed or sleeping page's card leaves")
        list.remove(b)
        #expect(list.entries.isEmpty)
        list.setPlaying(b, true)
        #expect(list.entries.isEmpty, "a gone card isn't made again")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/33")) func theCardPlaysAndPausesThePage() throws {
        let params = try #require(JSONSerialization.jsonObject(with: Data(NowPlayingList.playbackParams(.toggle).utf8)) as? [String: Any])
        #expect(params["expression"] as? String == NowPlayingList.playbackScript(.toggle))
        #expect(params["userGesture"] as? Bool == true, "a click on the card is a gesture")
        #expect(params["returnByValue"] as? Bool == true)
        #expect(NowPlayingList.playbackScript(.pause).contains("('pause')"))
        func said(_ v: String) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: ["result": ["type": "string", "value": v]]), as: UTF8.self)
        }
        #expect(NowPlayingList.playing(fromReply: said("playing")) == true)
        #expect(NowPlayingList.playing(fromReply: said("paused")) == false)
        #expect(NowPlayingList.playing(fromReply: said("other")) == nil)
        #expect(NowPlayingList.playing(fromReply: nil) == nil)
        var list = NowPlayingList()
        list.heard(a, music)
        list.setPlaying(a, false)
        #expect(list.entries == [.init(id: a, playing: false)])
    }
}
