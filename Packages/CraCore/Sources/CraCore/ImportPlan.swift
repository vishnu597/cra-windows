import Foundation

// Importers read another browser's on-disk stores (see docs/arc-reverse-engineering.md) into a
// neutral ImportPlan that `SidebarStore.apply` adds to the sidebar. The Mac and Windows apps read
// the same plans; only where the files live differs.

public struct ImportedItem {
    public var customTitle: String?
    public var pageTitle: String
    public var url: String?
    public var isFolder: Bool
    public var children: [ImportedItem]
    public var createdAt: Date
    /// Cached favicon file in the source browser, if any.
    public var faviconPath: String?
    /// A live folder's source and filter (Arc's GitHub live folder, #215): it keeps refreshing.
    public var liveFolder: LiveFolderData?
    /// The live item a tab in a live folder stands for (Arc: `liveItemID.url`).
    public var liveItemURL: String?
    /// The source's list a favorite came from, when it isn't its space's (Arc: the Top Apps
    /// container a space shows or borrows). The favorites tile counts each list once.
    public var favoritesList: String?

    public init(customTitle: String? = nil, pageTitle: String = "", url: String? = nil, isFolder: Bool = false,
                children: [ImportedItem] = [], createdAt: Date = Date(), faviconPath: String? = nil,
                liveFolder: LiveFolderData? = nil, liveItemURL: String? = nil, favoritesList: String? = nil) {
        self.favoritesList = favoritesList
        self.customTitle = customTitle
        self.pageTitle = pageTitle
        self.url = url
        self.isFolder = isFolder
        self.children = children
        self.createdAt = createdAt
        self.faviconPath = faviconPath
        self.liveFolder = liveFolder
        self.liveItemURL = liveItemURL
    }
}

public struct ImportedSpace {
    public var title: String
    public var emoji: String
    /// An SF Symbol shown instead of `emoji` (then empty): Arc's Icon-tab glyphs.
    public var symbol: String?
    public var theme: SpaceTheme?
    /// The space's own favorites (Arc: the top apps of the space's profile).
    public var favorites: [ImportedItem]
    public var pinned: [ImportedItem]
    public var today: [ImportedItem]
    /// The source browser's profile the space was on, when it is not Default (Arc, GitHub #131).
    public var profile: ImportedProfile?
    /// The source's list `favorites` is, when spaces share it (Zen's Essentials, Yab's shared tiles);
    /// nil for the space's own. A favorite's own `favoritesList` comes first.
    public var favoritesList: String?
    /// What the importer left out of this space, listed after the import.
    public var skipped: [ImportSkip]

    public init(title: String, emoji: String, symbol: String? = nil, theme: SpaceTheme? = nil, favorites: [ImportedItem] = [], pinned: [ImportedItem] = [],
                today: [ImportedItem] = [], profile: ImportedProfile? = nil, favoritesList: String? = nil, skipped: [ImportSkip] = []) {
        self.favoritesList = favoritesList
        self.skipped = skipped
        self.title = title
        self.emoji = emoji
        self.symbol = symbol
        self.theme = theme
        self.favorites = favorites
        self.pinned = pinned
        self.today = today
        self.profile = profile
    }
}

/// A Chromium profile of the source browser: its folder under `User Data` and the name it shows.
public struct ImportedProfile: Hashable {
    public var folder: String
    public var name: String

    public init(folder: String, name: String) {
        self.folder = folder
        self.name = name
    }
}

public struct ImportedArchiveEntry {
    public var customTitle: String?
    public var pageTitle: String
    public var url: String
    public var archivedAt: Date
    public var reason: ArchiveReason
    public var spaceTitle: String?
    /// Cached favicon file in the source browser, if any.
    public var faviconPath: String?

    public init(customTitle: String?, pageTitle: String, url: String, archivedAt: Date, reason: ArchiveReason, spaceTitle: String?,
                faviconPath: String? = nil) {
        self.faviconPath = faviconPath
        self.customTitle = customTitle
        self.pageTitle = pageTitle
        self.url = url
        self.archivedAt = archivedAt
        self.reason = reason
        self.spaceTitle = spaceTitle
    }
}

/// Air Traffic Control destinations name spaces by title; ids differ between browsers.
public enum ImportedLinkDestination: Equatable {
    case mostRecentSpace
    case space(title: String)
    case littleWindow(spaceTitle: String?)
}

public struct ImportedLinkRoute {
    public var match: LinkMatchStyle
    public var text: String
    public var destination: ImportedLinkDestination

    public init(match: LinkMatchStyle, text: String, destination: ImportedLinkDestination) {
        self.match = match
        self.text = text
        self.destination = destination
    }
}

/// The profile folder picked for a site in a Little Arc.
public struct ImportedSiteProfile: Equatable {
    public var site: String
    public var folder: String

    public init(site: String, folder: String) {
        self.site = site
        self.folder = folder
    }
}

public struct ImportedSettings {
    public var autoArchive: AutoArchiveThreshold?
    public var sidebarWidth: Double?
    public var showToolbar: Bool?
    public var toolbarShowsFullURL: Bool?
    public var linkRoutes: [ImportedLinkRoute] = []
    public var defaultLinkDestination: ImportedLinkDestination?
    /// Arc's domainToProfilePreferences, by site, so two reads of one file are equal.
    public var siteProfiles: [ImportedSiteProfile] = []

    public init() {}

    public var isEmpty: Bool {
        autoArchive == nil && sidebarWidth == nil && showToolbar == nil && toolbarShowsFullURL == nil && linkRoutes.isEmpty && defaultLinkDestination == nil
            && siteProfiles.isEmpty
    }
}

public struct ImportPlan {
    public var source: String
    public var spaces: [ImportedSpace] = []
    /// Favorites that belong to no imported space; they go to the focused space.
    public var favorites: [ImportedItem] = []
    public var archive: [ImportedArchiveEntry] = []
    public var settings = ImportedSettings()
    /// What the importer left out that belongs to no space it brings, listed after the import.
    public var skipped: [ImportSkip] = []
    /// Archived tabs the importer left out, listed when the archive comes over.
    public var archiveSkipped: [ImportSkip] = []

    public init(source: String) {
        self.source = source
    }

    public var tabCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? count($1.children) : 1) } }
        return spaces.reduce(count(favorites)) { $0 + count($1.favorites) + count($1.pinned) + count($1.today) }
    }

    public var folderCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? 1 + count($1.children) : 0) } }
        return spaces.reduce(count(favorites)) { $0 + count($1.favorites) + count($1.pinned) + count($1.today) }
    }

    /// The plan restricted to what the user picked.
    public func selecting(spaces: Set<Int>, favorites: Bool) -> ImportPlan {
        var p = self
        p.spaces = spaces.sorted().compactMap { $0 < self.spaces.count ? self.spaces[$0] : nil }
        if !favorites {
            p.favorites = []
            // What was left out of the favorites of no space goes with them.
            p.skipped.removeAll { $0.kind == .favorites }
        }
        return p
    }

    /// What the import counts and lists, a tile each: the spaces' pinned and Today tabs, the
    /// favorites, the archive when it comes over, and the skips that go with them. Favorites of no
    /// space are a list of their own ("").
    public func report(includeArchive: Bool) -> ImportReports {
        func urls(_ items: [ImportedItem]) -> [String] { items.flatMap { $0.isFolder ? urls($0.children) : [$0.url].compactMap { $0 } } }
        let lists = spaces.enumerated().map { i, sp in sp.favoritesList.map { "list " + $0 } ?? "space \(i)" }
        let favorites = urls(favorites).map { (list: "", url: $0) } + spaces.indices.flatMap { i in
            spaces[i].favorites.flatMap { item in urls([item]).map { (list: item.favoritesList.map { "list " + $0 } ?? lists[i], url: $0) } }
        }
        let skips = spaces.indices.flatMap { i in spaces[i].skipped.map { (list: $0.favoritesList.map { "list " + $0 } ?? lists[i], skip: $0) } }
            + (skipped + (includeArchive ? archiveSkipped : [])).map { (list: "", skip: $0) }
        return ImportReports(tabs: spaces.reduce(0) { $0 + $1.itemCount }, favorites: favorites, archive: includeArchive ? archive.count : 0, skipped: skips)
    }
}

extension ImportedSpace {
    /// The space's pinned and Today tabs, folders' tabs included.
    public var itemCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? count($1.children) : 1) } }
        return count(pinned) + count(today)
    }
}

public enum ImportError: LocalizedError, Equatable {
    case notFound(String)
    case unreadable(String)

    /// What the computer is called in messages.
    static var computer: String {
        #if os(Windows)
        "this PC"
        #else
        "this Mac"
        #endif
    }

    public var errorDescription: String? {
        switch self {
        case .notFound(let s): return "\(s) data was not found on \(Self.computer)."
        case .unreadable(let s): return "Could not read \(s)."
        }
    }
}

/// Chromium's timestamps: microseconds since 1601-01-01.
public enum ChromiumTime {
    /// Seconds between 1601-01-01 and 1970-01-01.
    public static let epochDelta: Int64 = 11_644_473_600
    public static var now: Int64 { from(Date()) }
    public static func from(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 + Double(epochDelta)) * 1_000_000) }
    public static func fromUnix(seconds s: Double) -> Int64 { Int64((s + Double(epochDelta)) * 1_000_000) }
    public static func date(_ chromiumMicros: Int64) -> Date {
        Date(timeIntervalSince1970: Double(chromiumMicros) / 1_000_000 - Double(epochDelta))
    }
}
