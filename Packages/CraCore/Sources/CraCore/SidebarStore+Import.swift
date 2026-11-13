import Foundation

extension SidebarStore {
    public struct ImportResult {
        public var spaces = 0
        public var tabs = 0
        public var folders = 0
        public var archived = 0
        public var spaceIDs: [UUID] = []
        /// The Cra profile each source profile of an imported space landed in.
        public var profiles = ImportProfileMap()

        public init() {}
    }

    /// Add a plan to the sidebar. Like Dia, every imported space is a new one (importing
    /// twice gives two of each), so people pick what to keep; a taken title gets a number
    /// ("JYSK 2"). Favorites on the current space skip URLs it already has. `replacing`
    /// spaces (a fresh install's empty one) are deleted afterwards and don't take titles.
    /// Favicons the source browser cached are copied into `favicons` (Cra's favicon folder).
    @discardableResult
    public func apply(_ plan: ImportPlan, includeArchive: Bool, includeSettings: Bool, replacing: [UUID] = [],
                      favicons: URL?) -> ImportResult {
        var result = ImportResult()

        // A pinned tab that has navigated still counts as present via its home URL.
        func existingURLs(under container: UUID) -> Set<String> {
            Set(tabs(under: container).flatMap { [$0.tab?.url, $0.tab?.savedURL].compactMap { $0 } })
        }

        // Favicons first, for every item (also ones skipped as duplicates).
        func copyFavicons(_ items: [ImportedItem]) {
            guard let favicons else { return }
            for it in items {
                if it.isFolder { copyFavicons(it.children); continue }
                guard let src = it.faviconPath, let url = it.url, let key = FaviconKey.key(for: url) else { continue }
                let dst = favicons.appendingPathComponent(FaviconKey.fileName(key))
                if !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(atPath: src, toPath: dst.path)
                }
            }
        }
        copyFavicons(plan.favorites)
        for sp in plan.spaces { copyFavicons(sp.favorites); copyFavicons(sp.pinned); copyFavicons(sp.today) }

        func insert(_ items: [ImportedItem], into parent: UUID, skip: Set<String>, pinned: Bool) {
            var skip = skip
            for it in items {
                if let live = it.liveFolder {
                    insertLiveFolder(it, live, into: parent, pinned: pinned)
                } else if it.isFolder {
                    let name = it.customTitle ?? it.pageTitle
                    // Re-importing must not duplicate folders: reuse one with the same name.
                    let folder: SidebarItem
                    if let existing = children(of: parent).first(where: { $0.isFolder && ($0.title ?? "") == name }) {
                        folder = existing
                    } else {
                        folder = createFolder(named: name, in: parent)
                        setExpanded(folder.id, false)
                        result.folders += 1
                    }
                    insert(it.children, into: folder.id, skip: existingURLs(under: folder.id), pinned: pinned)
                } else if let url = it.url, !skip.contains(url) {
                    skip.insert(url)
                    var tab = SidebarItem.tab(url, title: it.pageTitle, parent: parent)
                    tab.title = it.customTitle
                    tab.createdAt = it.createdAt
                    // An open tab was alive in the other browser: auto-archive counts from the import,
                    // not from when the tab was made (Dia keeps tabs for weeks with auto-clean off).
                    if var t = tab.tab {
                        t.timeLastActiveAt = pinned ? it.createdAt : clock.now
                        if self.items[parent]?.isLiveFolder == true { t.liveItemURL = it.liveItemURL }
                        tab.data = .tab(t)
                    }
                    insertItem(tab, into: parent, at: nil)
                    result.tabs += 1
                }
            }
        }

        // A space has one GitHub live folder: importing again fills the one it has.
        func insertLiveFolder(_ it: ImportedItem, _ live: LiveFolderData, into parent: UUID, pinned: Bool) {
            guard let sid = self.spaceID(ofItem: parent), !isIncognito(space: sid) else { return }
            let folder: SidebarItem
            if let existing = self.liveFolder(live.source, inSpace: sid) {
                folder = existing
            } else {
                folder = createFolder(named: it.customTitle ?? it.pageTitle, in: parent)
                self.items[folder.id]?.liveFolder = live
                setExpanded(folder.id, false)
                result.folders += 1
            }
            insert(it.children.filter { $0.liveItemURL != nil }, into: folder.id, skip: existingURLs(under: folder.id), pinned: pinned)
        }

        let current = focusedSpace.favoritesContainerID
        insert(plan.favorites, into: current, skip: existingURLs(under: current), pinned: true)

        // Archive entries and link routes name spaces by title: point them at this import's spaces.
        var imported: [String: UUID] = [:]
        func spaceID(titled title: String) -> UUID? {
            imported[title.lowercased()] ?? orderedSpaces.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.id
        }
        func freeTitle(_ title: String) -> String {
            let taken = Set(orderedSpaces.filter { !replacing.contains($0.id) }.map { $0.title.lowercased() })
            guard taken.contains(title.lowercased()) else { return title }
            var n = 2
            while taken.contains("\(title) \(n)".lowercased()) { n += 1 }
            return "\(title) \(n)"
        }

        // A source profile's spaces go on the Cra profile of its name; the rest stay on Default.
        for sp in plan.spaces {
            let space = createSpace(title: freeTitle(sp.title), emoji: sp.emoji, symbol: sp.symbol, theme: sp.theme, focus: false)
            if let source = sp.profile {
                let folder = result.profiles.folders[source.folder] ?? importedProfile(named: source.name).directoryName
                result.profiles.folders[source.folder] = folder
                if let p = profiles.first(where: { $0.directoryName == folder }) { setProfile(p.id, forSpace: space.id) }
            } else {
                result.profiles.folders["Default"] = "Default"
            }
            result.spaces += 1
            result.spaceIDs.append(space.id)
            if imported[sp.title.lowercased()] == nil { imported[sp.title.lowercased()] = space.id }
            // With shared favorites (#154) the profile picks which list the space shows.
            let favorites = self.space(space.id)?.favoritesContainerID ?? space.favoritesContainerID
            insert(sp.favorites, into: favorites, skip: existingURLs(under: favorites), pinned: true)
            insert(sp.pinned, into: space.pinnedContainerID, skip: existingURLs(under: space.pinnedContainerID), pinned: true)
            insert(sp.today, into: space.todayContainerID, skip: existingURLs(under: space.todayContainerID), pinned: false)
        }
        for id in replacing { deleteSpace(id) }

        if includeArchive {
            let known = Set(archive.compactMap { $0.item.tab?.url })
            for e in plan.archive where !known.contains(e.url) {
                var item = SidebarItem.tab(e.url, title: e.pageTitle, parent: nil)
                item.title = e.customTitle
                let sid = e.spaceTitle.flatMap(spaceID(titled:))
                appendArchived(ArchivedItem(archivedAt: e.archivedAt, reason: e.reason, sourceSpaceID: sid, wasPinned: false, item: item))
                result.archived += 1
            }
        }

        if includeSettings {
            if let a = plan.settings.autoArchive { settings.autoArchive = a }
            if let w = plan.settings.sidebarWidth { prefs.sidebarWidth = SidebarWidth.clamped(w) }
            if let t = plan.settings.showToolbar { settings.showToolbar = t }
            if let f = plan.settings.toolbarShowsFullURL { settings.toolbarShowsFullURL = f }
            // Air Traffic Control, pointed at the spaces of the same name.
            func destination(_ d: ImportedLinkDestination) -> LinkDestination {
                switch d {
                case .mostRecentSpace: return .mostRecentSpace
                case .littleWindow(let title): return .littleWindow(space: title.flatMap(spaceID(titled:)))
                case .space(let title):
                    return spaceID(titled: title).map { .space($0) } ?? .mostRecentSpace
                }
            }
            if let d = plan.settings.defaultLinkDestination { settings.defaultLinkDestination = destination(d) }
            for r in plan.settings.linkRoutes where !settings.linkRoutes.contains(where: { $0.match == r.match && $0.text == r.text }) {
                settings.linkRoutes.append(LinkRoute(match: r.match, text: r.text, destination: destination(r.destination)))
            }
        }
        touchAfterImport()
        return result
    }

    /// The Cra profile a source profile becomes: one already there of the same name is reused, so
    /// importing again (or rebuilding from Arc) doesn't add "Work" twice.
    private func importedProfile(named name: String) -> BrowserProfile {
        profiles.first { $0.name == name } ?? createProfile(name: name)
    }

    // MARK: Rebuild from Arc (GitHub #131)

    /// Spaces an import from before Cra kept Arc's profiles left on Default, that Arc has on a
    /// profile of their own (matched by name).
    public func arcProfileMoves(_ plan: ImportPlan) -> [ArcProfileRebuild.Move] {
        let cra = orderedSpaces.map { ArcProfileRebuild.CraSpace(id: $0.id, title: $0.title, movable: $0.profileID == nil && !isIncognito(space: $0.id)) }
        let arc = plan.spaces.map { ArcProfileRebuild.ArcSpace(title: $0.title, folder: $0.profile?.folder, name: $0.profile?.name ?? "Default") }
        return ArcProfileRebuild.moves(cra: cra, arc: arc)
    }

    /// Puts each space on the Cra profile its Arc profile becomes; what Arc's profiles map to.
    @discardableResult
    public func applyArcProfileMoves(_ moves: [ArcProfileRebuild.Move]) -> ImportProfileMap {
        var map = ImportProfileMap(folders: ["Default": "Default"])
        for m in moves where spaces[m.spaceID] != nil {
            let profile = map.folders[m.folder].flatMap { f in profiles.first { $0.directoryName == f } } ?? importedProfile(named: m.profileName)
            map.folders[m.folder] = profile.directoryName
            setProfile(profile.id, forSpace: m.spaceID)
        }
        return map
    }
}

extension SidebarStore.ImportResult {
    /// What the import added, for the toast after it: "Imported 2 spaces and 31 tabs from Chrome".
    public func summary(from source: String) -> String {
        func count(_ n: Int, _ one: String) -> String? { n == 0 ? nil : "\(n) \(one)\(n == 1 ? "" : "s")" }
        let parts = [count(spaces, "space"), count(tabs, "tab"), count(folders, "folder"), count(archived, "archived tab")].compactMap { $0 }
        guard let last = parts.last else { return "Nothing new to import from \(source)" }
        let list = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
        return "Imported \(list) from \(source)"
    }
}
