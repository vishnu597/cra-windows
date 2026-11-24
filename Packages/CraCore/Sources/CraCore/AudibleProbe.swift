import Foundation

/// The speaker on a tab that plays sound (TabSound, issue #28) where the engine doesn't say
/// whether a page is audible (Windows' stock CEF; the Mac's engine tells Cra through
/// `didChangeAudible`). The page's own script says whether a player in it makes sound: playing,
/// not at its end, not muted, with some volume, in the top frame or a same-origin frame.
/// Players in frames from other sites, and Web Audio, can't be heard this way.
public enum AudibleProbe {
    /// The expression `Runtime.evaluate` returns: true when a player in the page makes sound.
    public static let script = """
    (() => {
      const docs = [document];
      for (const f of document.querySelectorAll('iframe,frame')) {
        try { if (f.contentDocument) docs.push(f.contentDocument); } catch (e) {}
      }
      return docs.some(d => [...d.querySelectorAll('video,audio')].some(m =>
        !m.paused && !m.ended && m.readyState > 2 && !m.muted && m.volume > 0));
    })()
    """

    /// The DevTools `Runtime.evaluate` parameters: by value, without a user gesture.
    public static var evaluateParams: String {
        let params: [String: Any] = ["expression": script, "returnByValue": true, "userGesture": false]
        let data = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the page said it makes sound. nil when there's no clean answer (the page closed,
    /// is loading a new document, the script threw): the tab keeps what it showed.
    public static func answer(fromReply reply: String?) -> Bool? {
        guard let data = reply?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["exceptionDetails"] == nil,
              let result = json["result"] as? [String: Any], result["type"] as? String == "boolean" else { return nil }
        return result["value"] as? Bool
    }

    /// Chrome's "recently audible" (AudibleHold's 2 s, as the Mac keeps it): a tab that
    /// goes quiet keeps its speaker until it has been quiet for `hold`, so a gap between tracks
    /// or a probe that lands on a pause doesn't make the row flicker.
    public struct Tracker: Equatable, Sendable {
        public static let hold: TimeInterval = AudibleHold.quiet
        /// How often Windows asks each page.
        public static let pollInterval: TimeInterval = 1

        /// When each tab last made sound (now, for a tab that plays).
        private var heardAt: [UUID: Date] = [:]

        public init() {}

        /// Records a page's answer (nil: none, which keeps the tab as it was).
        public mutating func note(_ id: UUID, audible: Bool?, now: Date) {
            if audible == true { heardAt[id] = now }
        }

        /// Forgets tabs whose page is gone: no page, no sound.
        public mutating func keep(only ids: Set<UUID>) {
            heardAt = heardAt.filter { ids.contains($0.key) }
        }

        /// The tabs that show the speaker now.
        public func audible(now: Date) -> Set<UUID> {
            Set(heardAt.filter { now.timeIntervalSince($0.value) < Self.hold }.keys)
        }
    }
}
