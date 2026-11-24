import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What a folder's preview lists and how big it is (Arc 1.171, Previews.FolderPreviewState and
/// FolderPreviewItem; docs/arc-reverse-engineering.md "Folder previews"), the same rules as the Mac's
/// FolderPreviewController and the Windows one. Every tab under the folder, nested folders and
/// splits included, most recently used first; the search keeps the rows whose title and address
/// hold every word typed.
public enum FolderPreviewList {
    public struct Entry: Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var url: String
        public var iconKey: String?
        public var lastVisit: Date
        /// Unread (FolderPreviewItem.isBadged).
        public var badged: Bool

        public init(id: UUID, title: String, url: String, iconKey: String?, lastVisit: Date, badged: Bool) {
            self.id = id
            self.title = title
            self.url = url
            self.iconKey = iconKey
            self.lastVisit = lastVisit
            self.badged = badged
        }
    }

    public static let width: CGFloat = 240
    public static let maxHeight: CGFloat = 320
    public static let searchHeight: CGFloat = 48
    /// A row's highlight, inside its 45 pt pitch.
    public static let rowFill: CGFloat = 44
    public static let gapFromSidebar: CGFloat = 4
    /// The card stays this far inside the window.
    public static let windowInset: CGFloat = 18
    /// The row turns hovered, and 0.45 s later the preview opens.
    public static let openDelay: TimeInterval = 0.45
    /// Crossing from the folder to the preview leaves both for a moment.
    public static let closeGrace: TimeInterval = 0.06

    /// One row is 98 pt; six and more stop at 320 and scroll. Filtering keeps the size.
    public static func height(rows n: Int) -> CGFloat {
        min(searchHeight + 1 + FolderPreviewRows.listInset + CGFloat(max(n, 1)) * FolderPreviewRows.rowPitch, maxHeight)
    }

    /// The entries whose title and address hold every word of `query`, ignoring case.
    public static func filter(_ entries: [Entry], query: String) -> [Entry] {
        entries.filter { matches(title: $0.title, url: $0.url, query: query) }
    }

    /// Whether a row with this title and address stays for `query` (an empty one keeps all).
    public static func matches(title: String, url: String, query: String) -> Bool {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return true }
        let hay = (title + " " + url).lowercased()
        return words.allSatisfy(hay.contains)
    }

    /// The card's top, centred on the row and kept `windowInset` inside the window (all in one
    /// space, y down).
    public static func top(rowMidY: CGFloat, height: CGFloat, windowTop: CGFloat, windowBottom: CGFloat) -> CGFloat {
        let wanted = rowMidY - height / 2
        return max(min(wanted, windowBottom - windowInset - height), windowTop + windowInset)
    }

    /// "Just now", "15 hours ago", "1 week ago": the Mac's RelativeDateTimeFormatter (full,
    /// numeric) in English, for platforms without it.
    public static func age(of date: Date, now: Date) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "Just now" }
        let units: [(String, Double)] = [("year", 365 * 86400), ("month", 30 * 86400), ("week", 7 * 86400),
                                         ("day", 86400), ("hour", 3600), ("minute", 60)]
        for (name, length) in units where s >= length {
            let n = Int(s / length)
            return "\(n) \(name)\(n == 1 ? "" : "s") ago"
        }
        return "Just now"
    }
}

extension SidebarStore {
    /// Every tab under the folder (nested folders and splits included), most recently used first
    /// (FolderPreviewState.allPossibleChildren, sorted by lastVisitDate).
    public func folderPreviewEntries(_ folderID: UUID) -> [FolderPreviewList.Entry] {
        tabs(under: folderID).map { t in
            FolderPreviewList.Entry(id: t.id, title: t.displayTitle, url: t.tab?.url ?? "", iconKey: t.tab?.iconKey,
                                    lastVisit: t.tab?.timeLastActiveAt ?? t.createdAt, badged: t.isUnread)
        }
        .sorted { $0.lastVisit > $1.lastVisit }
    }
}
