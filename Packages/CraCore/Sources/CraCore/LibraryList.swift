import Foundation

/// The Library's pages Cra has, in the order of Arc's rail (which also lists Boosts). The Mac's
/// LibraryView and Windows' Library column draw them.
public enum LibraryPage: String, CaseIterable, Sendable {
    case media, downloads, easels, spaces, archive

    public var title: String {
        switch self {
        case .media: "Media"
        case .downloads: "Downloads"
        case .easels: "Easels"
        case .spaces: "Spaces"
        case .archive: "Archived Tabs"
        }
    }

    /// The rail's SF Symbol (WinGlyph maps it on Windows).
    public var symbol: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .downloads: "arrow.down.circle"
        case .easels: "pencil.and.scribble"
        case .spaces: "square.on.square"
        case .archive: "archivebox"
        }
    }

    public var selectedSymbol: String {
        switch self {
        case .media: "photo.fill.on.rectangle.fill"
        case .easels: symbol
        default: symbol + ".fill"
        }
    }

    public var searchPrompt: String {
        switch self {
        case .media: "Search Media…"
        case .downloads: "Search Downloads…"
        case .easels: "Search Easels…"
        default: "Search Archive…"
        }
    }
}

/// The Library's sizes, measured on Arc 1.170 (LibraryView on the Mac has the whole list).
public enum LibraryLayout {
    /// The page rail's width.
    public static let rail = 113.0
    /// Arc's Library sidebar was 70 pt wider than the 347 pt tab sidebar.
    public static let extraWidth = 70.0
    /// A day's header and an item's row.
    public static let headerHeight = 40.0
    public static let rowHeight = 56.0
}

/// What a Library page lists: its items that match the search, newest first, under a header per
/// day ("Today", "Yesterday", then the date), and what it says when there are none.
public enum LibraryList {
    public struct Section<Item> {
        public let title: String
        public let items: [Item]
    }

    /// The archived tabs whose title or address holds the search (archive is newest first).
    public static func archive(_ archive: [ArchivedItem], matching query: String, now: Date = Date(),
                               calendar: Calendar = .current, locale: Locale = .current) -> [Section<ArchivedItem>] {
        let needle = needle(query)
        let shown = needle.isEmpty ? archive : archive.filter {
            $0.item.displayTitle.lowercased().contains(needle) || ($0.item.tab?.url.lowercased().contains(needle) ?? false)
        }
        return grouped(shown, date: { $0.archivedAt }, now: now, calendar: calendar, locale: locale)
    }

    /// The finished downloads still on disk whose file name holds the search, newest first
    /// (downloads.json keeps them oldest first).
    public static func downloads(_ entries: [DownloadHistory.Entry], matching query: String, exists: (String) -> Bool,
                                 now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current)
        -> [Section<DownloadHistory.Entry>] {
        let needle = needle(query)
        let all = entries.reversed().filter { exists($0.path) }
        let shown = needle.isEmpty ? all : all.filter { fileName($0.path).lowercased().contains(needle) }
        return grouped(shown, date: { $0.date }, now: now, calendar: calendar, locale: locale)
    }

    /// The easels whose title holds the search, by the day each was last edited (in the order
    /// given: the Mac's EaselFiles lists them newest first).
    public static func easels<Easel>(_ easels: [Easel], title: (Easel) -> String, edited: (Easel) -> Date, matching query: String,
                                     now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> [Section<Easel>] {
        let needle = needle(query)
        let shown = needle.isEmpty ? easels : easels.filter { title($0).lowercased().contains(needle) }
        return grouped(shown, date: edited, now: now, calendar: calendar, locale: locale)
    }

    /// A path's last component, for either platform's separators.
    public static func fileName(_ path: String) -> String {
        String(path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? Substring(path))
    }

    /// "Today", "Yesterday", or the day in the locale's medium style.
    public static func dayTitle(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// The page's empty state: nothing at all yet, or nothing matching the search.
    public struct Empty: Equatable, Sendable {
        public let symbol: String
        public let title: String
        public let detail: String?

        public init(symbol: String, title: String, detail: String?) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
        }
    }

    public static func empty(_ page: LibraryPage, hasAny: Bool) -> Empty {
        guard !hasAny else { return Empty(symbol: page.symbol, title: "No matches", detail: nil) }
        switch page {
        case .media:
            return Empty(symbol: page.symbol, title: "Nothing here yet!",
                         detail: "Screenshots, pictures and videos in the folders you show appear here.")
        case .downloads:
            return Empty(symbol: page.symbol, title: "Nothing here yet!", detail: "Files you download show up here.")
        case .easels:
            // Arc's empty Easels page.
            return Empty(symbol: page.symbol, title: "Out of ideas!", detail: "Choose File ▸ New Easel to create a new Easel.")
        case .spaces, .archive:
            return Empty(symbol: page.symbol, title: "Nothing here yet!", detail: "Tabs you close end up here.")
        }
    }

    private static func needle(_ query: String) -> String {
        query.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// In the items' order, a section per day as each day first appears.
    private static func grouped<T>(_ items: [T], date: (T) -> Date, now: Date, calendar: Calendar, locale: Locale) -> [Section<T>] {
        var order: [String] = []
        var groups: [String: [T]] = [:]
        for item in items {
            let title = dayTitle(date(item), now: now, calendar: calendar, locale: locale)
            if groups[title] == nil { order.append(title) }
            groups[title, default: []].append(item)
        }
        return order.map { Section(title: $0, items: groups[$0] ?? []) }
    }
}
