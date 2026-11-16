import Foundation

/// The question a page is asked before tab sleeping closes it on Windows, where Chromium's
/// discard and Cra's isolated-world recorder (the Mac's BrowserManager.sleepProbe) aren't
/// there: in the page's own world, does it hold something it would lose? Edited form fields,
/// a playing, unmuted audio or video element, and the page's own onbeforeunload each keep it
/// awake. A false "awake" only costs memory; a false "asleep" loses the user's work, so
/// anything unclear (an exception, no reply) keeps the page.
public enum TabSleepProbe {
    public static let script = """
    (() => {
      const edited = e => e.isContentEditable ? false
        : e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked
        : e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected)
        : e.type === 'hidden' || e.type === 'submit' || e.type === 'button' ? false
        : (e.value ?? '') !== (e.defaultValue ?? '');
      for (const e of document.querySelectorAll('input, textarea, select')) {
        if (edited(e)) return 'typed';
      }
      for (const m of document.querySelectorAll('audio, video')) {
        if (!m.paused && !m.ended && !m.muted && m.volume > 0) return 'sound';
      }
      if (typeof window.onbeforeunload === 'function') return 'beforeunload';
      return '';
    })()
    """

    /// The DevTools `Runtime.evaluate` parameters that ask it, by value, without a user gesture.
    public static var evaluateParams: String {
        let params: [String: Any] = ["expression": script, "returnByValue": true, "userGesture": false]
        let data = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The reply: "" when the page may sleep, else why it stays awake. Anything but a clean
    /// string answer ("probe failed", "no reply") keeps it awake too.
    public static func refusal(fromReply reply: String?) -> String {
        guard let data = reply?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "no reply" }
        guard json["exceptionDetails"] == nil else { return "probe failed" }
        guard let value = (json["result"] as? [String: Any])?["value"] as? String else { return "no reply" }
        return value
    }
}

public extension TabSleepPolicy {
    /// Settings ▸ Tabs' line under the switch: which tabs stay in memory, before the user finds
    /// out (the Mac's TabsPane.tabSleepNote, without its memory-pressure sweep).
    static func settingsNote(timerOn: Bool, after: TabSleepThreshold) -> String {
        let note = "A tab out of sight that long reloads when you open it. Tabs playing sound or holding text you typed stay in memory."
        guard timerOn, timer(after).keepsRecentTabs else { return note }
        return note + " So do the 10 tabs you used last."
    }
}
