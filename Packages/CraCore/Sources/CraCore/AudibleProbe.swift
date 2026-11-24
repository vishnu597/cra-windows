import Foundation

/// The speaker on a tab that plays sound (TabSound, issue #28) where the engine doesn't say
/// whether a page is audible (Windows' stock CEF; the Mac's engine tells Cra through
/// `didChangeAudible`). The page's own script says whether a player in it makes sound: playing,
/// not at its end, not muted, with some volume, in the top frame or a same-origin frame.
/// Players in frames from other sites, and Web Audio, can't be heard this way.
public enum AudibleProbe {
    /// The expression `Runtime.evaluate` returns: a JSON string, `{"audible":a,"controllable":c,"video":v}`.
    /// `controllable`: a heard player runs 5 s or more (or is a stream), the media Chrome's
    /// media controls would show, so a notification ding makes no player card (#411).
    /// `video`: a heard player is a video.
    public static let script = """
    (() => {
      const docs = [document];
      for (const f of document.querySelectorAll('iframe,frame')) {
        try { if (f.contentDocument) docs.push(f.contentDocument); } catch (e) {}
      }
      const heard = docs.flatMap(d => [...d.querySelectorAll('video,audio')]).filter(m =>
        !m.paused && !m.ended && m.readyState > 2 && !m.muted && m.volume > 0);
      return JSON.stringify({audible: heard.length > 0,
        controllable: heard.some(m => !isFinite(m.duration) || m.duration >= 5),
        video: heard.some(m => m.tagName === 'VIDEO')});
    })()
    """

    /// What a page said about its sound.
    public struct Answer: Equatable, Sendable {
        public var audible: Bool
        public var controllable: Bool
        public var video: Bool

        public init(audible: Bool, controllable: Bool = false, video: Bool = false) {
            self.audible = audible
            self.controllable = audible && controllable
            self.video = audible && video
        }
    }

    /// The DevTools `Runtime.evaluate` parameters: by value, without a user gesture.
    public static var evaluateParams: String {
        let params: [String: Any] = ["expression": script, "returnByValue": true, "userGesture": false]
        let data = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// What the page said. nil when there's no clean answer (the page closed, is loading a new
    /// document, the script threw): the tab keeps what it showed.
    public static func answer(fromReply reply: String?) -> Answer? {
        guard let data = reply?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["exceptionDetails"] == nil,
              let value = (json["result"] as? [String: Any])?["value"] as? String,
              let o = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
              let audible = o["audible"] as? Bool else { return nil }
        return Answer(audible: audible, controllable: o["controllable"] as? Bool ?? false, video: o["video"] as? Bool ?? false)
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
