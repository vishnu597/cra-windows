import CraCore
import Foundation
import Testing

/// What a page says before Windows' tab sleeping closes it.
struct TabSleepProbeTests {
    @Test func aCleanAnswerLetsThePageSleepAndAnythingElseKeepsIt() {
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"string","value":""}}"#) == "")
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"string","value":"typed"}}"#) == "typed")
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"object"},"exceptionDetails":{"text":"x"}}"#) == "probe failed")
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"undefined"}}"#) == "no reply")
        #expect(TabSleepProbe.refusal(fromReply: nil) == "no reply")
        #expect(TabSleepProbe.refusal(fromReply: "not json") == "no reply")
    }

    @Test func theParamsAskForTheScriptByValue() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(TabSleepProbe.evaluateParams.utf8)) as? [String: Any])
        #expect(json["expression"] as? String == TabSleepProbe.script)
        #expect(json["returnByValue"] as? Bool == true)
        #expect(json["userGesture"] as? Bool == false)
    }

    @Test func soundAndRecorderFailureBothRefuseSleeping() {
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"string","value":"sound"}}"#) == "sound")
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"string","value":"no recorder"}}"#) == "no recorder")
        #expect(TabSleepProbe.refusal(fromReply: #"{"result":{"type":"boolean","value":false}}"#) == "no reply")
    }

    @Test func theSettingsNoteSaysWhichTabsStay() {
        #expect(TabSleepPolicy.settingsNote(timerOn: true, after: .fourHours).hasSuffix("So do the 10 tabs you used last."))
        #expect(!TabSleepPolicy.settingsNote(timerOn: true, after: .fifteenMinutes).contains("10 tabs"))
        #expect(!TabSleepPolicy.settingsNote(timerOn: false, after: .fourHours).contains("10 tabs"))
    }
}
