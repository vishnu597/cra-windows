import CraCore
import Foundation
import Testing

/// The speaker on a playing tab on Windows (#28), where stock CEF doesn't say a page is audible:
/// the page's script answers, and the speaker holds 2 s after the sound stops, as on the Mac.
struct WindowsAudibleTests {
    private let t = Date(timeIntervalSince1970: 0)
    private func reply(_ result: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["result": result]), as: UTF8.self)
    }

    private func said(_ value: String) -> String { reply(["type": "string", "value": value]) }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/28")) func thePageSaysWhetherItMakesSound() {
        #expect(AudibleProbe.answer(fromReply: said(#"{"audible":true,"controllable":true,"video":true}"#))
            == AudibleProbe.Answer(audible: true, controllable: true, video: true))
        #expect(AudibleProbe.answer(fromReply: said(#"{"audible":false,"controllable":false,"video":false}"#)) == AudibleProbe.Answer(audible: false))
        #expect(AudibleProbe.answer(fromReply: nil) == nil)
        #expect(AudibleProbe.answer(fromReply: reply(["type": "undefined"])) == nil)
        #expect(AudibleProbe.answer(fromReply: said("not json")) == nil)
        #expect(AudibleProbe.answer(fromReply: #"{"result":{"type":"object"},"exceptionDetails":{"text":"x"}}"#) == nil)
        #expect(AudibleProbe.Answer(audible: false, controllable: true, video: true) == AudibleProbe.Answer(audible: false),
                "a quiet page has no controllable player")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/28")) func onlyAPlayerThatCanBeHeardCounts() throws {
        for rule in ["!m.paused", "!m.ended", "!m.muted", "m.volume > 0", "contentDocument", "m.duration >= 5", "isFinite"] {
            #expect(AudibleProbe.script.contains(rule), "\(rule)")
        }
        #expect(!AudibleProbe.script.contains("play()") && !AudibleProbe.script.contains("pause()"), "it only looks")
        let params = try #require(JSONSerialization.jsonObject(with: Data(AudibleProbe.evaluateParams.utf8)) as? [String: Any])
        #expect(params["expression"] as? String == AudibleProbe.script)
        #expect(params["returnByValue"] as? Bool == true)
        #expect(params["userGesture"] as? Bool == false)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/28")) func theSpeakerHoldsTwoSecondsAfterTheSoundStops() {
        let a = UUID(), b = UUID()
        var tracker = AudibleProbe.Tracker()
        tracker.note(a, audible: true, now: t)
        tracker.note(b, audible: false, now: t)
        #expect(tracker.audible(now: t) == [a])
        tracker.note(a, audible: false, now: t.addingTimeInterval(1))
        #expect(tracker.audible(now: t.addingTimeInterval(1.9)) == [a], "a gap between tracks doesn't flicker")
        #expect(tracker.audible(now: t.addingTimeInterval(2)) == [])
        #expect(AudibleProbe.Tracker.pollInterval < AudibleProbe.Tracker.hold, "a playing page is asked again before its hold ends")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/28")) func noAnswerKeepsTheTabAndAClosedPageGoesQuiet() {
        let a = UUID()
        var tracker = AudibleProbe.Tracker()
        tracker.note(a, audible: true, now: t)
        tracker.note(a, audible: nil, now: t.addingTimeInterval(1))
        #expect(tracker.audible(now: t.addingTimeInterval(1)) == [a])
        tracker.keep(only: [])
        #expect(tracker.audible(now: t.addingTimeInterval(1)) == [])
    }
}
