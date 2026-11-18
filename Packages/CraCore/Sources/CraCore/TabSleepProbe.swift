import Foundation

/// The question a page is asked before tab sleeping closes it on Windows, where Chromium's
/// discard and Cra's isolated-world recorder (the Mac's BrowserManager.sleepProbe) aren't
/// there. Trusted input is recorded before the page's scripts run, as PageScript does on the
/// Mac: a framework updating defaultValue cannot erase evidence of the user's edit. Running
/// Web Audio contexts, media elements and the page's own onbeforeunload also keep it awake.
/// A false "awake" only costs memory; a false "asleep" loses work, so anything unclear keeps it.
public enum TabSleepProbe {
    /// Install in each new main-frame context, before page scripts can make an AudioContext or
    /// hear input. The recorder retains no text copies and exposes only the reason to stay awake.
    /// A full navigation replaces the context; a same-document SPA route must keep its edits.
    public static let documentStartScript = """
    (() => {
      if (Object.prototype.hasOwnProperty.call(window, '__craTabSleep')) return;
      const typed = new Set(), contexts = new Set();
      let failed = false;
      const edited = e => e.isContentEditable ? e.textContent.trim() !== ''
        : e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked
        : e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected)
        : e.type === 'hidden' || e.type === 'submit' || e.type === 'button' ? false
        : (e.value ?? '') !== '';
      Object.defineProperty(window, '__craTabSleep', { value: () => {
        for (const e of typed) {
          if (!e.isConnected) { typed.delete(e); continue; }
          if (edited(e)) return 'typed';
        }
        for (const context of contexts) {
          if (context.state === 'closed') contexts.delete(context);
          else if (context.state === 'running') return 'sound';
        }
        return failed ? 'probe failed' : '';
      } });
      addEventListener('input', event => {
        if (!event.isTrusted) return;
        const target = event.composedPath()[0];
        if (!(target instanceof Element)) return;
        typed.add(target.isContentEditable ? target.closest('[contenteditable]') ?? target : target);
      }, true);
      for (const name of ['AudioContext', 'webkitAudioContext']) {
        const Original = window[name];
        if (typeof Original !== 'function') continue;
        try {
          const Wrapped = new Proxy(Original, { construct(target, args, newTarget) {
            const context = Reflect.construct(target, args, newTarget);
            contexts.add(context);
            context.addEventListener('statechange', () => {
              if (context.state === 'closed') contexts.delete(context);
            });
            return context;
          } });
          window[name] = Wrapped;
          if (window[name] !== Wrapped) failed = true;
        } catch { failed = true; }
      }
    })()
    """

    /// Ask the document-start recorder first, then retain the original DOM checks as a fallback.
    public static let script = """
    (() => {
      if (typeof window.__craTabSleep !== 'function') return 'no recorder';
      const recorded = window.__craTabSleep();
      if (typeof recorded !== 'string') return 'probe failed';
      if (recorded) return recorded;
      const edited = e => e.isContentEditable ? false
        : e.type === 'checkbox' || e.type === 'radio' ? e.checked !== e.defaultChecked
        : e.tagName === 'SELECT' ? [...e.options].some(o => o.selected !== o.defaultSelected)
        : e.type === 'hidden' || e.type === 'submit' || e.type === 'button' ? false
        : (e.value ?? '') !== '' && (e.value ?? '') !== (e.defaultValue ?? '');
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
