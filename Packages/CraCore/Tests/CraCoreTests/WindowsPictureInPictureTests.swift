import CraCore
import Foundation
import Testing

/// Windows' Picture in Picture (View ▸ Picture in Picture and leaving a video tab) asks the page
/// through DevTools with these.
struct WindowsPictureInPictureTests {
    @Test func theRequestCarriesAUserGestureTheLookDoesNot() throws {
        let request = PictureInPictureRequest.script(engine: .chromium, automatic: false, request: true)
        let asked = try #require(JSONSerialization.jsonObject(with: Data(PictureInPictureRequest.evaluateParams(request, userGesture: true).utf8)) as? [String: Any])
        #expect(asked["expression"] as? String == request)
        #expect(asked["userGesture"] as? Bool == true)
        #expect(asked["awaitPromise"] as? Bool == true)
        let look = try #require(JSONSerialization.jsonObject(with: Data(PictureInPictureRequest.evaluateParams(PictureInPictureRequest.exitScript, userGesture: false).utf8)) as? [String: Any])
        #expect(look["userGesture"] as? Bool == false)
    }

    @Test func repliesReadAsAnswers() {
        let reply = #"{"result":{"type":"string","value":"video"}}"#
        #expect(PictureInPictureRequest.Answer(PictureInPictureRequest.value(fromReply: reply)) == .video)
        #expect(PictureInPictureRequest.step(after: .init(PictureInPictureRequest.value(fromReply: reply))) == .request)
        #expect(PictureInPictureRequest.value(fromReply: #"{"result":{},"exceptionDetails":{}}"#) == nil)
        #expect(PictureInPictureRequest.Answer(PictureInPictureRequest.value(fromReply: nil)) == .lost)
    }

    @Test func theExitOnlyReturnsAVideoThatIsOut() {
        #expect(PictureInPictureRequest.exitScript.contains("document.pictureInPictureElement ?"))
        #expect(!PictureInPictureRequest.exitScript.contains("requestPictureInPicture"))
    }

    @Test func windowsRunsPictureInPictureFromTheCommandBar() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["pictureInPicture"]?.inCommandBar == true)
    }
}
