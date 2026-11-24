import Foundation

/// A tab's back and forward list on Windows, kept across a relaunch (GitHub #273, the Mac's
/// PageHistory). Stock CEF can't put serialized navigations back into a new page as the Mac's
/// engine does (`Cra.restoreHistory`), so Windows keeps the addresses and titles
/// (DevTools `Page.getNavigationHistory`) and steps through them itself: while the restored page
/// has no page of its own behind it, Back replaces it with the saved one before it
/// (`location.replace`, so Chromium's own list doesn't grow), and Forward likewise ahead. Page
/// state (scroll position, form contents) doesn't come back. Saved in the data folder's
/// PageList/<tab id>.json, one file a tab; incognito pages never get one.
public struct PageList: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var url: String
        public var title: String

        public init(url: String, title: String = "") {
            self.url = url
            self.title = title
        }
    }

    public var entries: [Entry]
    /// The current entry's place in `entries`.
    public var index: Int
    public var savedAt: Date

    /// Pages kept on each side of the current one, as Chrome's session service keeps them.
    public static let kept = 6

    public init(entries: [Entry], index: Int, savedAt: Date) {
        self.entries = entries
        self.index = min(max(0, index), max(0, entries.count - 1))
        self.savedAt = savedAt
    }

    public var current: Entry? { entries.indices.contains(index) ? entries[index] : nil }
    public var canGoBack: Bool { index > 0 && entries.indices.contains(index) }
    public var canGoForward: Bool { index + 1 < entries.count }

    /// The list read from a `Page.getNavigationHistory` reply
    /// (`{"currentIndex": n, "entries": [{"url", "title"}, …]}`), nil for anything else.
    public static func live(history json: String) -> (entries: [Entry], index: Int)? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let index = object["currentIndex"] as? Int,
              let raw = object["entries"] as? [[String: Any]], raw.indices.contains(index) else { return nil }
        return (raw.map { Entry(url: $0["url"] as? String ?? "", title: $0["title"] as? String ?? "") }, index)
    }

    /// Whether a new page for a tab now at `tabURL` steps through this list: only while it ends
    /// where the tab is (a pinned tab put back on its page, or a page that moved on, starts
    /// fresh) and there is somewhere to go. Not on Chromium's own pages (PageHistory).
    public func restores(at tabURL: String) -> Bool {
        current?.url == tabURL && (canGoBack || canGoForward) && !PageHistory.isChromiumOwnPage(tabURL)
    }

    /// The tab's list now, from what the page's own list is (`live`, `liveIndex`) on top of this
    /// one, the list the page started with (as Back and Forward have stepped it: its `index` is
    /// where the page's first entry stands, never a merged list's): while the page has only its one
    /// entry it stands in the saved list's place, and the saved pages ahead stay; once it has
    /// gone on to others, the saved pages ahead of where it started are gone, as a browser's are.
    /// Kept to `kept` pages on each side.
    public func merged(live: [Entry], liveIndex: Int, savedAt: Date) -> PageList {
        guard !live.isEmpty, live.indices.contains(liveIndex) else { return self }
        var all: [Entry], at: Int
        if live.count == 1, entries.indices.contains(index) {
            all = entries
            all[index] = live[0]
            at = index
        } else {
            all = Array(entries.prefix(index)) + live
            at = index + liveIndex
        }
        let start = max(0, at - Self.kept), end = min(all.count, at + Self.kept + 1)
        return PageList(entries: Array(all[start..<end]), index: at - start, savedAt: savedAt)
    }

    /// A page's own list alone, the first time it is saved.
    public static func fresh(live: [Entry], liveIndex: Int, savedAt: Date) -> PageList {
        PageList(entries: [], index: 0, savedAt: savedAt).merged(live: live, liveIndex: liveIndex, savedAt: savedAt)
    }

    /// Back with nothing behind in the page itself: the saved page to replace it with, and the
    /// list stepped back; nil when there is none.
    public func back(pageCanGoBack: Bool) -> (url: String, list: PageList)? {
        guard !pageCanGoBack, canGoBack else { return nil }
        var list = self
        list.index -= 1
        return (list.entries[list.index].url, list)
    }

    /// Forward with nothing ahead in the page, while it is still on its one entry (a page that
    /// went on to others has left the saved pages ahead behind).
    public func forward(pageCanGoForward: Bool, pageEntries: Int) -> (url: String, list: PageList)? {
        guard !pageCanGoForward, pageEntries <= 1, canGoForward else { return nil }
        var list = self
        list.index += 1
        return (list.entries[list.index].url, list)
    }

    /// The script that puts `url` in the page's place without adding to its list.
    public static func replaceScript(_ url: String) -> String {
        let quoted = (try? JSONSerialization.data(withJSONObject: [url], options: .withoutEscapingSlashes)).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return "location.replace(\(quoted)[0])"
    }
}
