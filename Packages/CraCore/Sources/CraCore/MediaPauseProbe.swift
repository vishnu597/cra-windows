import Foundation

/// Pause All Media (#438) where the engine has no Cra.pauseMedia (Windows' stock CEF): the
/// page's own script pauses what plays and says what it did, in Cra.pauseMedia's words, so
/// `MediaPause.outcome` reads both the same way.
///
/// It runs in the page's top frame and the same-origin frames it can reach. A playing element
/// is paused, and checked again 0.3 s later (Cra.pauseMedia's wait for the page's own pause
/// handler): one playing again kept playing. Frames from other sites are paused by
/// `subframeScript`, run in each of them, which can't answer.
public enum MediaPauseProbe {
    /// The expression `Runtime.evaluate` awaits: a JSON string, `{"playing":false}` when nothing
    /// played, else `{"playing":true,"session":false,"paused":n,"resisted":n}`.
    public static let script = """
    (async () => {
      const docs = [document];
      for (const f of document.querySelectorAll('iframe,frame')) {
        try { if (f.contentDocument) docs.push(f.contentDocument); } catch (e) {}
      }
      const playing = docs.flatMap(d => [...d.querySelectorAll('video,audio')]).filter(m => !m.paused && !m.ended);
      if (!playing.length) return JSON.stringify({playing: false});
      playing.forEach(m => { try { m.pause(); } catch (e) {} });
      await new Promise(r => setTimeout(r, 300));
      const resisted = playing.filter(m => !m.paused).length;
      return JSON.stringify({playing: true, session: false, paused: playing.length - resisted, resisted});
    })()
    """

    /// Run in every frame but the top one: pauses its media, says nothing.
    public static let subframeScript = "document.querySelectorAll('video,audio').forEach(m => { try { m.pause(); } catch (e) {} })"

    /// The DevTools `Runtime.evaluate` parameters: awaited, by value, without a user gesture.
    public static var evaluateParams: String {
        let params: [String: Any] = ["expression": script, "awaitPromise": true, "returnByValue": true, "userGesture": false]
        let data = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The page's answer from `Runtime.evaluate`'s reply. nil when there's no clean answer (the
    /// page closed, the script threw): the page counts as having said nothing.
    public static func answer(fromReply reply: String?) -> MediaPause.EngineAnswer? {
        guard let data = reply?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["exceptionDetails"] == nil,
              let value = (json["result"] as? [String: Any])?["value"] as? String,
              let o = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else { return nil }
        guard o["playing"] as? Bool == true else { return MediaPause.EngineAnswer() }
        return MediaPause.EngineAnswer(session: o["session"] as? Bool ?? false, paused: o["paused"] as? Int ?? 0,
                                       resisted: o["resisted"] as? Int ?? 0)
    }
}
