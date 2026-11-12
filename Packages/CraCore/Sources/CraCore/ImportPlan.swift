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

    public init(customTitle: String? = nil, pageTitle: String = "", url: String? = nil, isFolder: Bool = false,
                children: [ImportedItem] = [], createdAt: Date = Date(), faviconPath: String? = nil,
                liveFolder: LiveFolderData? = nil, liveItemURL: String? = nil) {
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
    public var theme: SpaceTheme?
    /// The space's own favorites (Arc: the top apps of the space's profile).
    public var favorites: [ImportedItem]
    public var pinned: [ImportedItem]
    public var today: [ImportedItem]
    /// The source browser's profile the space was on, when it is not Default (Arc, GitHub #131).
    public var profile: ImportedProfile?

    public init(title: String, emoji: String, theme: SpaceTheme?, favorites: [ImportedItem] = [], pinned: [ImportedItem] = [],
                today: [ImportedItem] = [], profile: ImportedProfile? = nil) {
        self.title = title
        self.emoji = emoji
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

    public init(customTitle: String?, pageTitle: String, url: String, archivedAt: Date, reason: ArchiveReason, spaceTitle: String?) {
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

public struct ImportedSettings {
    public var autoArchive: AutoArchiveThreshold?
    public var sidebarWidth: Double?
    public var showToolbar: Bool?
    public var toolbarShowsFullURL: Bool?
    public var linkRoutes: [ImportedLinkRoute] = []
    public var defaultLinkDestination: ImportedLinkDestination?

    public init() {}

    public var isEmpty: Bool {
        autoArchive == nil && sidebarWidth == nil && showToolbar == nil && toolbarShowsFullURL == nil && linkRoutes.isEmpty && defaultLinkDestination == nil
    }
}

public struct ImportPlan {
    public var source: String
    public var spaces: [ImportedSpace] = []
    /// Favorites that belong to no imported space; they go to the focused space.
    public var favorites: [ImportedItem] = []
    public var archive: [ImportedArchiveEntry] = []
    public var settings = ImportedSettings()

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
