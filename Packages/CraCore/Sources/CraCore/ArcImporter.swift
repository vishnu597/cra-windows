import Foundation

private func refDate(_ v: Any?) -> Date {
    if let d = v as? Double { return Date(timeIntervalSinceReferenceDate: d) }
    return Date()
}

/// Arc stores `[id, object, id, object…]` for ordered dictionaries.
private func pairs(_ list: Any?) -> [(String, [String: Any])] {
    guard let arr = list as? [Any] else { return [] }
    var out: [(String, [String: Any])] = []
    var i = 0
    while i + 1 < arr.count {
        if let id = arr[i] as? String, let obj = arr[i + 1] as? [String: Any] { out.append((id, obj)); i += 2 }
        else { i += 1 }
    }
    return out
}

/// Arc wraps an enum case's value as `{case: {_0: value}}`.
private func tagged<T>(_ value: Any?, _ key: String) -> T? {
    ((value as? [String: Any])?[key] as? [String: Any])?["_0"] as? T
}

/// Arc's sidebar, archive, Air Traffic Control and window files (StorableSidebar.json and
/// friends), the same on the Mac and on Windows. The apps say where Arc keeps them and pass
/// Arc's preferences (the Mac's are in its defaults).
public enum ArcImporter {
    /// Arc's own preferences an import carries over; nil where Arc never stored one.
    public struct Preferences: Equatable {
        /// `autoArchiveTimeThreshold`.
        public var autoArchive: String?
        /// View ▸ Show Toolbar (`topBarURLEnabled`).
        public var showsToolbar: Bool?
        /// "Show Full URL" on the toolbar address (`toolbarShowFullURLsEnabledPreference`).
        public var showsFullURL: Bool?

        public init(autoArchive: String? = nil, showsToolbar: Bool? = nil, showsFullURL: Bool? = nil) {
            self.autoArchive = autoArchive
            self.showsToolbar = showsToolbar
            self.showsFullURL = showsFullURL
        }
    }

    /// Arc's Chromium profiles: Default and "Profile <n>", one per profile a space can be on.
    public static func userData(in supportDir: URL) -> URL { supportDir.appendingPathComponent("User Data", isDirectory: true) }

    public static func isAvailable(in supportDir: URL) -> Bool {
        FileManager.default.fileExists(atPath: supportDir.appendingPathComponent("StorableSidebar.json").path)
    }

    public static func plan(supportDir: URL, preferences: Preferences,
                            symbolExists: (String) -> Bool = { _ in false }) throws -> ImportPlan {
        let url = supportDir.appendingPathComponent("StorableSidebar.json")
        guard let data = try? Data(contentsOf: url) else { throw ImportError.notFound("Arc") }
        return try plan(sidebar: data, supportDir: supportDir, preferences: preferences, symbolExists: symbolExists)
    }

    /// The plan from a StorableSidebar.json's contents (favicons, the archive, link routes and
    /// profiles still come from `supportDir`). `symbolExists`: whether the platform has an SF Symbol
    /// of a name, for Arc's `symbol` icons (`ArcSpaceIcon`); Windows has none.
    public static func plan(sidebar data: Data, supportDir: URL, preferences: Preferences,
                            symbolExists: (String) -> Bool = { _ in false }) throws -> ImportPlan {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [[String: Any]] else { throw ImportError.unreadable("Arc's sidebar") }
        var plan = ImportPlan(source: "Arc")
        guard let main = containers.first(where: { $0["spaces"] != nil }) else { return plan }
        // A damaged file can list an id twice: the later entry wins, as when Arc decodes it.
        let items = Dictionary(pairs(main["items"]), uniquingKeysWith: { _, later in later })
        var spaceTitleByID: [String: String] = [:]

        func convert(_ id: String) -> ImportedItem? {
            guard let it = items[id], let dataDict = it["data"] as? [String: Any] else { return nil }
            let custom = it["title"] as? String
            let created = refDate(it["createdAt"])
            let childIDs = it["childrenIds"] as? [String] ?? []
            if let tab = dataDict["tab"] as? [String: Any] {
                guard let u = tab["savedURL"] as? String, !u.isEmpty else { return nil }
                return ImportedItem(customTitle: custom, pageTitle: tab["savedTitle"] as? String ?? "", url: u, createdAt: created,
                                    faviconPath: faviconFile(forItemID: id, in: supportDir), liveItemURL: tagged(tab["liveItemID"], "url"))
            }
            if let list = dataDict["list"] as? [String: Any] {
                return ImportedItem(customTitle: custom, pageTitle: custom ?? "Folder", url: nil, isFolder: true,
                                    children: childIDs.compactMap(convert), createdAt: created,
                                    liveFolder: liveFolder(list["automaticLiveFolderData"]))
            }
            if dataDict["splitView"] != nil || dataDict["tabGroup"] != nil {
                // Flatten split views into their tabs.
                let kids = childIDs.compactMap(convert)
                return kids.count == 1 ? kids[0] : ImportedItem(customTitle: custom ?? "Split", pageTitle: "", url: nil, isFolder: true, children: kids, createdAt: created)
            }
            return nil
        }

        // Each space is on a Chromium profile in User Data, named as Arc's space menu shows it.
        let profileNames = ChromiumImporter.profileNames(userData: userData(in: supportDir))

        // Favorites (topApps): one container per profile, shared by that profile's spaces.
        var favoritesByProfile: [(profile: Data?, items: [ImportedItem])] = []
        var allFavorites: [ImportedItem] = []
        for (_, it) in items {
            guard let d = it["data"] as? [String: Any], let c = d["itemContainer"] as? [String: Any],
                  let type = c["containerType"] as? [String: Any], let top = type["topApps"] as? [String: Any] else { continue }
            let favs = (it["childrenIds"] as? [String] ?? []).compactMap(convert)
            allFavorites += favs
            if let profile = top["_0"] as? [String: Any] { favoritesByProfile.append((canonical(profile), favs)) }
        }

        for (sid, space) in pairs(main["spaces"]) {
            let title = space["title"] as? String ?? "Space"
            spaceTitleByID[sid] = title
            // An emoji, an Icon-tab glyph as Cra's symbol in that slot, or no icon (a dot, #252).
            let icon = ArcSpaceIcon.icon((space["customInfo"] as? [String: Any])?["iconType"] as? [String: Any],
                                         symbolExists: symbolExists)
            var pinnedID: String?, todayID: String?
            if let ids = space["containerIDs"] as? [Any] {
                var i = 0
                while i + 1 < ids.count {
                    if let k = ids[i] as? String, let v = ids[i + 1] as? String {
                        if k == "pinned" { pinnedID = v } else if k == "unpinned" { todayID = v }
                    }
                    i += 2
                }
            }
            // A space without a theme is Arc's default dark purple, close to Ink. Not the next
            // preset: that shifted every later space onto another colour (issue #30).
            var sp = ImportedSpace(title: title, emoji: icon.emoji, symbol: icon.symbol, theme: ArcThemeImport.theme(from: space) ?? SpaceTheme.presets[0])
            let profile = (space["profile"] as? [String: Any]).flatMap(canonical)
            sp.favorites = favoritesByProfile.first { $0.profile != nil && $0.profile == profile }?.items ?? allFavorites
            sp.profile = ImportProfileMap.arcProfileFolder(space["profile"]).map { ImportedProfile(folder: $0, name: profileNames[$0] ?? $0) }
            if let p = pinnedID, let c = items[p] { sp.pinned = (c["childrenIds"] as? [String] ?? []).compactMap(convert) }
            if let t = todayID, let c = items[t] { sp.today = (c["childrenIds"] as? [String] ?? []).compactMap(convert) }
            plan.spaces.append(sp)
        }

        // Archive
        if let adata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableArchiveItems.json")),
           let aroot = try? JSONSerialization.jsonObject(with: adata) as? [String: Any],
           let aitems = aroot["items"] as? [Any] {
            for case let e as [String: Any] in aitems {
                guard let si = e["sidebarItem"] as? [String: Any], let d = si["data"] as? [String: Any],
                      let tab = d["tab"] as? [String: Any], let u = tab["savedURL"] as? String, !u.isEmpty else { continue }
                let reason = (e["reason"] as? String) == "auto" ? ArchiveReason.auto : .manual
                var spaceTitle: String?
                if let src = e["source"] as? [String: Any], let sp = src["space"] as? [String: Any], let id = sp["_0"] as? String { spaceTitle = spaceTitleByID[id] }
                plan.archive.append(ImportedArchiveEntry(customTitle: si["title"] as? String, pageTitle: tab["savedTitle"] as? String ?? "",
                                                         url: u, archivedAt: refDate(e["archivedAt"]), reason: reason, spaceTitle: spaceTitle))
            }
            plan.archive.sort { $0.archivedAt > $1.archivedAt }
            if plan.archive.count > 1500 { plan.archive.removeLast(plan.archive.count - 1500) }
        }

        // Settings
        if let wdata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableWindows.json")),
           let wroot = try? JSONSerialization.jsonObject(with: wdata) as? [String: Any],
           let prefs = wroot["sidebarViewPreferences"] as? [String: Any], let w = prefs["sidebarWidth"] as? Double {
            plan.settings.sidebarWidth = w
        }
        if let threshold = preferences.autoArchive {
            plan.settings.autoArchive = AutoArchiveThreshold(rawValue: threshold)
        }
        plan.settings.showToolbar = preferences.showsToolbar
        plan.settings.toolbarShowsFullURL = preferences.showsFullURL
        if let ldata = try? Data(contentsOf: supportDir.appendingPathComponent("StorableLinkRouting.json")),
           let lroot = try? JSONSerialization.jsonObject(with: ldata) as? [String: Any] {
            plan.settings.defaultLinkDestination = linkDestination(lroot["defaultDestination"], spaceTitles: spaceTitleByID)
            plan.settings.linkRoutes = (lroot["rules"] as? [[String: Any]] ?? []).compactMap { linkRoute($0, spaceTitles: spaceTitleByID) }
        }
        return plan
    }

    /// Arc's `automaticLiveFolderData` for a GitHub folder: `dataSource {github: {}}`, `filter
    /// {github: {_0: {attributes, hiddenRepositories [{owner, name}]}}}`, `hiddenItems [{url: {_0}}]`.
    /// Its `lastFetch` stays behind, so the folder refreshes as soon as Cra runs (#215).
    public static func liveFolder(_ value: Any?) -> LiveFolderData? {
        guard let data = value as? [String: Any], (data["dataSource"] as? [String: Any])?["github"] != nil else { return nil }
        var live = LiveFolderData()
        if let filter: [String: Any] = tagged(data["filter"], "github") {
            if let bits = filter["attributes"] as? Int { live.filter.attributes = GitHubLiveFilter.Attributes(rawValue: bits).intersection(.all) }
            live.filter.hiddenRepositories = (filter["hiddenRepositories"] as? [[String: Any]] ?? []).compactMap { r in
                guard let owner = r["owner"] as? String, let name = r["name"] as? String else { return nil }
                return "\(owner)/\(name)"
            }
        }
        live.hiddenItems = (data["hiddenItems"] as? [Any] ?? []).compactMap { tagged($0, "url") }
        return live
    }

    /// One Air Traffic Control rule: `sourceComponents[0].componentType.urlMatch` is
    /// `{_0: {contains: {}} | {matches: {}}, _1: text}`.
    private static func linkRoute(_ rule: [String: Any], spaceTitles: [String: String]) -> ImportedLinkRoute? {
        guard let dest = linkDestination(rule["destination"], spaceTitles: spaceTitles),
              let component = (rule["sourceComponents"] as? [[String: Any]])?.first,
              let type = component["componentType"] as? [String: Any],
              let urlMatch = type["urlMatch"] as? [String: Any],
              let text = urlMatch["_1"] as? String else { return nil }
        let style: LinkMatchStyle = (urlMatch["_0"] as? [String: Any])?["matches"] != nil ? .equals : .contains
        return ImportedLinkRoute(match: style, text: text, destination: dest)
    }

    /// `{littleArc: {_0: <profile>}}` or `{space: {_0: {mostRecent: {}}}}`; a specific
    /// space is recognised by its id anywhere inside either. Arc's editor never wrote a
    /// Little Arc with a space, but one written by hand loaded in that space's profile;
    /// Cra's Little Window route can name the space (#258).
    private static func linkDestination(_ value: Any?, spaceTitles: [String: String]) -> ImportedLinkDestination? {
        guard let d = value as? [String: Any] else { return nil }
        func title(_ v: Any) -> String? {
            if let s = v as? String { return spaceTitles[s] }
            if let o = v as? [String: Any] { return o.values.lazy.compactMap(title).first }
            if let a = v as? [Any] { return a.lazy.compactMap(title).first }
            return nil
        }
        if let little = d["littleArc"] { return .littleWindow(spaceTitle: title(little)) }
        guard let space = d["space"] else { return nil }
        return title(space).map { .space(title: $0) } ?? .mostRecentSpace
    }

    /// Arc caches sidebar favicons as 32x32 PNGs named md5(item id).
    public static func faviconFile(forItemID id: String, in supportDir: URL) -> String? {
        let path = supportDir.appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true)
            .appendingPathComponent(MD5.hex(Data(id.utf8))).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// A profile value in one spelling, to tell two spaces' profiles apart (an NSDictionary
    /// compare on the Mac; Foundation elsewhere doesn't bridge JSON objects to it).
    static func canonical(_ value: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
