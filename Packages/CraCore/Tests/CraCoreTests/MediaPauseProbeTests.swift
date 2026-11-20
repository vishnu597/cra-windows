import CraCore
import Foundation
import Testing

/// Pause All Media on an engine without Cra.pauseMedia (Windows): the page script's answer.
struct MediaPauseProbeTests {
    func reply(_ value: String) -> String {
        let o: [String: Any] = ["result": ["type": "string", "value": value]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: o), as: UTF8.self)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func aQuietPageSaysNothingPlayed() {
        let answer = MediaPauseProbe.answer(fromReply: reply(#"{"playing":false}"#))
        #expect(answer == MediaPause.EngineAnswer())
        #expect(MediaPause.outcome(answer: answer, playingBefore: false, playingAfter: false) == .quiet)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func pausedAndResistedElementsCount() {
        let paused = MediaPauseProbe.answer(fromReply: reply(#"{"playing":true,"session":false,"paused":2,"resisted":0}"#))
        #expect(paused == MediaPause.EngineAnswer(paused: 2))
        #expect(MediaPause.outcome(answer: paused, playingBefore: false, playingAfter: false) == .paused)

        let resisted = MediaPauseProbe.answer(fromReply: reply(#"{"playing":true,"session":false,"paused":0,"resisted":1}"#))
        #expect(resisted == MediaPause.EngineAnswer(resisted: 1))
        #expect(MediaPause.outcome(answer: resisted, playingBefore: false, playingAfter: false) == .keptPlaying,
                "a player that plays on after pause() isn't reported as paused")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func noCleanAnswerIsNoAnswer() {
        #expect(MediaPauseProbe.answer(fromReply: nil) == nil)
        #expect(MediaPauseProbe.answer(fromReply: #"{"message":"no page"}"#) == nil)
        #expect(MediaPauseProbe.answer(fromReply: #"{"result":{"type":"object"},"exceptionDetails":{"text":"x"}}"#) == nil)
        #expect(MediaPauseProbe.answer(fromReply: reply("not json")) == nil)
    }

    @Test func theEvaluationAwaitsTheScriptByValueWithoutAGesture() throws {
        let params = try #require(JSONSerialization.jsonObject(with: Data(MediaPauseProbe.evaluateParams.utf8)) as? [String: Any])
        #expect(params["expression"] as? String == MediaPauseProbe.script)
        #expect(params["awaitPromise"] as? Bool == true)
        #expect(params["returnByValue"] as? Bool == true)
        #expect(params["userGesture"] as? Bool == false)
        #expect(!MediaPauseProbe.script.contains("play()"), "it pauses and never plays")
        #expect(!MediaPauseProbe.subframeScript.contains("play()"))
    }

    @Test func windowsRunsPauseAllMediaFromTheCommandBarWithoutKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["pauseAllMedia"]?.shortcuts == [])
        #expect(windows["pauseAllMedia"]?.inCommandBar == true)
    }
}
