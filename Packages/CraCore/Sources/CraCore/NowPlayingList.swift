import Foundation

/// Arc's "now playing" player at the bottom of the sidebar (issue #33) on an engine that reports
/// neither the page's audible state nor its media session (Windows' stock CEF), from what the
/// page's own script says (AudibleProbe). The Mac's NowPlaying rules:
/// - a tab gets a card when a player in it starts making sound, oldest card first;
/// - only media Chrome's controls would show makes one: a ding under 5 s doesn't (#411);
/// - a card stays while its tab is paused, and leaves when it's dismissed, its page closes or
///   sleeps, or it navigates while quiet (a playlist moving on keeps it);
/// - the sidebar shows the cards of tabs that aren't on screen.
public struct NowPlayingList: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: UUID
        public var playing: Bool
        /// A video plays (the Mac's card offers Picture in Picture for it).
        public var hasVideo: Bool

        public init(id: UUID, playing: Bool, hasVideo: Bool = false) {
            self.id = id
            self.playing = playing
            self.hasVideo = hasVideo
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// The page answered: its card follows the sound at once (the card's own play and pause
    /// show without waiting for the speaker's hold), and a controllable player makes one.
    public mutating func heard(_ id: UUID, _ answer: AudibleProbe.Answer) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].playing = answer.audible
            if answer.audible { entries[i].hasVideo = answer.video }
        } else if answer.controllable {
            entries.append(Entry(id: id, playing: true, hasVideo: answer.video))
        }
    }

    /// The tab went to another address. `audible`: it made sound in the last 2 s.
    public mutating func navigated(_ id: UUID, audible: Bool) {
        if !audible { remove(id) }
    }

    /// The card's play or pause took (the page's answer to `playbackParams`).
    public mutating func setPlaying(_ id: UUID, _ playing: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].playing = playing
    }

    /// Dismissed (✕), or its page is gone.
    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// The tabs that still have a page: the others' cards leave.
    public mutating func keep(only ids: Set<UUID>) {
        entries.removeAll { !ids.contains($0.id) }
    }

    /// The cards the sidebar shows, oldest first (the newest is the front card).
    public func shown(onScreen: Set<UUID>) -> [Entry] {
        entries.filter { !onScreen.contains($0.id) }
    }

    // MARK: Play and pause

    /// What a card's button asks the page.
    public enum Playback: String, Sendable {
        /// Pause what plays, else play the player that played last (or the first).
        case toggle
        case pause
    }

    /// The page's media elements, as the Mac's sidebar player plays and pauses a page without
    /// a media session handler. It answers "playing" or "paused".
    public static func playbackScript(_ op: Playback) -> String {
        """
        ((op) => {
          const docs = [document];
          for (const f of document.querySelectorAll('iframe,frame')) {
            try { if (f.contentDocument) docs.push(f.contentDocument); } catch (e) {}
          }
          const media = docs.flatMap(d => [...d.querySelectorAll('video,audio')]);
          const playing = media.filter(m => !m.paused && !m.ended);
          if (op === 'pause' || playing.length) { media.forEach(m => { try { m.pause(); } catch (e) {} }); return 'paused'; }
          const last = media.find(m => m.currentTime > 0 && !m.ended) ?? media[0];
          if (!last) return 'paused';
          try { last.play(); } catch (e) {}
          return 'playing';
        })('\(op.rawValue)')
        """
    }

    /// The DevTools `Runtime.evaluate` parameters, with a user gesture: a click on the card is one.
    public static func playbackParams(_ op: Playback) -> String {
        let params: [String: Any] = ["expression": playbackScript(op), "returnByValue": true, "userGesture": true]
        let data = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether the page plays after the card's button: nil when it didn't answer.
    public static func playing(fromReply reply: String?) -> Bool? {
        guard let data = reply?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["exceptionDetails"] == nil,
              let value = (json["result"] as? [String: Any])?["value"] as? String,
              value == "playing" || value == "paused" else { return nil }
        return value == "playing"
    }
}
