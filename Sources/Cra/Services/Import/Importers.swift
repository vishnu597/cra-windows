import Foundation

// The Mac's importers for Arc and Dia: where their files are and their preferences. The plan
// types, Arc's sidebar reader and `SidebarStore.apply` are in CraCore (ImportPlan.swift,
// ArcImporter.swift, SidebarStore+Import.swift), which Windows reads too.

private func refDate(_ v: Any?) -> Date {
    if let d = v as? Double { return Date(timeIntervalSinceReferenceDate: d) }
    return Date()
}

// MARK: - Arc

extension ArcImporter {
    /// CRA_ARC_DIR points a test instance at a made-up profile (Tests/Fixtures/Arc).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_ARC_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Arc", isDirectory: true)

    static var isAvailable: Bool { isAvailable(in: supportDir) }

    /// Arc's Chromium profiles: Default and "Profile <n>", one per profile a space can be on.
    static var userData: URL { userData(in: supportDir) }

    /// Arc's View ▸ Show Toolbar (topBarURLEnabled, off by default); nil when Arc never stored it.
    static var showsToolbar: Bool? {
        UserDefaults(suiteName: "company.thebrowser.Browser")?.object(forKey: "topBarURLEnabled") as? Bool
    }

    /// Arc's "Show Full URL" on the toolbar address (off by default); nil when Arc never stored it.
    static var showsFullURL: Bool? {
        UserDefaults(suiteName: "company.thebrowser.Browser")?.object(forKey: "toolbarShowFullURLsEnabledPreference") as? Bool
    }

    /// Arc's preferences, from its defaults.
    static var preferences: Preferences {
        Preferences(autoArchive: UserDefaults(suiteName: "company.thebrowser.Browser")?.string(forKey: "autoArchiveTimeThreshold"),
                    showsToolbar: showsToolbar, showsFullURL: showsFullURL)
    }

    static func plan() throws -> ImportPlan { try plan(supportDir: supportDir, preferences: preferences, symbolExists: symbolExists) }

    /// Whether macOS has an SF Symbol of this name, for Arc's `symbol` space icons.
    static func symbolExists(_ name: String) -> Bool { NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil }

    /// The plan from a StorableSidebar.json's contents (favicons and profiles still come from
    /// `supportDir`).
    static func plan(sidebar data: Data) throws -> ImportPlan {
        try plan(sidebar: data, supportDir: supportDir, preferences: preferences, symbolExists: symbolExists)
    }

    /// Arc caches sidebar favicons as 32x32 PNGs named md5(item id).
    static func faviconFile(forItemID id: String) -> String? { faviconFile(forItemID: id, in: supportDir) }
}

// MARK: - Dia

enum DiaImporter {
    /// CRA_DIA_DIR points a test instance at a made-up profile (Tests/Fixtures/Dia).
    static let supportDir = ProcessInfo.processInfo.environment["CRA_DIA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dia", isDirectory: true)
    static var userData: URL { supportDir.appendingPathComponent("User Data", isDirectory: true) }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: supportDir.appendingPathComponent("StorableProfileContainers.json").path) || hasEncryptedSidebar
    }

    /// Dia 1.55 and later: the sidebar is in encrypted tabs.db files, read with the Keychain secret.
    static var hasEncryptedSidebar: Bool { !DiaSidebar.databases(userData: userData).isEmpty }

    /// With the "Dia Safe Storage" secret the spaces come from Dia's sidebar database; without
    /// it (or from an older Dia) from the files Dia kept before 1.55, which no longer follow
    /// the sidebar: the open tabs as of then and the bookmarks bar. A secret that opens no
    /// sidebar database throws rather than fall back to those stale files.
    static func plan(secret: String? = nil) throws -> ImportPlan {
        guard isAvailable else { throw ImportError.notFound("Dia") }
        var plan = ImportPlan(source: "Dia")
        if let secret, hasEncryptedSidebar {
            plan.spaces = DiaSidebar.spaces(userData: userData, rootKey: ChromiumCrypto.key(fromSecret: secret))
            if plan.spaces.isEmpty { throw ImportError.unreadable("Dia's spaces and tabs") }
        } else {
            addLegacySidebar(to: &plan)
        }
        addArchive(to: &plan)
        return plan
    }

    private static func addLegacySidebar(to plan: inout ImportPlan) {
        // Open tabs and the favorites container.
        if let data = try? Data(contentsOf: supportDir.appendingPathComponent("StorableProfileContainers.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containers = root["containers"] as? [[String: Any]] {
            var openTabs: [ImportedItem] = []
            for c in containers {
                let idInfo = c["id"] as? [String: Any]
                let kind = idInfo?["container"] as? [String: Any]
                let isFavorites = kind?["favorites"] != nil
                for tab in c["tabs"] as? [[String: Any]] ?? [] {
                    guard let contents = tab["contents"] as? [[String: Any]] else { continue }
                    for content in contents {
                        guard let variant = content["variant"] as? [String: Any], let web = variant["webContent"] as? [String: Any],
                              let w = web["_0"] as? [String: Any], let url = w["url"] as? String else { continue }
                        let item = ImportedItem(pageTitle: w["title"] as? String ?? "", url: url, createdAt: refDate(tab["creationDate"]))
                        if isFavorites { plan.favorites.append(item) } else { openTabs.append(item) }
                    }
                }
            }
            if !openTabs.isEmpty { plan.spaces.append(ImportedSpace(title: "Dia", emoji: "🌀", theme: nil, today: openTabs)) }
        }

        // Bookmarks: Dia keeps imported Arc spaces as folders on the bookmarks bar.
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        for prof in profiles where prof == "Default" || prof.hasPrefix("Profile ") {
            let bm = supportDir.appendingPathComponent("User Data/\(prof)/Bookmarks")
            guard let data = try? Data(contentsOf: bm), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let roots = root["roots"] as? [String: Any], let bar = roots["bookmark_bar"] as? [String: Any] else { continue }
            func convert(_ node: [String: Any]) -> ImportedItem? {
                let name = node["name"] as? String ?? ""
                if node["type"] as? String == "url", let u = node["url"] as? String {
                    return ImportedItem(customTitle: name.isEmpty ? nil : name, pageTitle: name, url: u)
                }
                if node["type"] as? String == "folder" {
                    let kids = (node["children"] as? [[String: Any]] ?? []).compactMap(convert)
                    return ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids)
                }
                return nil
            }
            for child in bar["children"] as? [[String: Any]] ?? [] {
                guard let item = convert(child) else { continue }
                if item.isFolder {
                    if item.pageTitle.lowercased() == "favorites" { plan.favorites.append(contentsOf: item.children.filter { !$0.isFolder }) }
                    else if !item.children.isEmpty {
                        if let i = plan.spaces.firstIndex(where: { $0.title == item.pageTitle }) { plan.spaces[i].pinned.append(contentsOf: item.children) }
                        else { plan.spaces.append(ImportedSpace(title: item.pageTitle, emoji: "📁", theme: nil, pinned: item.children)) }
                    }
                } else {
                    plan.favorites.append(item)
                }
            }
            if let other = roots["other"] as? [String: Any], let kids = (other["children"] as? [[String: Any]])?.compactMap(convert), !kids.isEmpty {
                plan.spaces.append(ImportedSpace(title: "Other Bookmarks", emoji: "🔖", theme: nil, pinned: kids))
            }
        }
    }

    private static func addArchive(to plan: inout ImportPlan) {
        // Auto-archive store (best effort; shape varies between Dia versions).
        if let data = try? Data(contentsOf: supportDir.appendingPathComponent("StorableAutoArchive.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let containers = root["containers"] as? [[String: Any]] {
            for c in containers {
                for t in c["archivedTabs"] as? [[String: Any]] ?? [] {
                    if let (url, title) = firstURL(in: t) {
                        plan.archive.append(ImportedArchiveEntry(customTitle: nil, pageTitle: title, url: url,
                                                                 archivedAt: refDate(t["archivedAt"] ?? t["archiveDate"] ?? t["date"]), reason: .auto, spaceTitle: "Dia"))
                    }
                }
            }
        }
    }

    private static func firstURL(in obj: Any) -> (String, String)? {
        if let d = obj as? [String: Any] {
            if let u = d["url"] as? String, u.hasPrefix("http") { return (u, d["title"] as? String ?? "") }
            for v in d.values { if let r = firstURL(in: v) { return r } }
        } else if let a = obj as? [Any] {
            for v in a { if let r = firstURL(in: v) { return r } }
        }
        return nil
    }
}

// MARK: - Applying

extension SidebarStore {
    /// Add a plan to the sidebar, its favicons copied into Cra's favicon cache.
    @discardableResult
    func apply(_ plan: ImportPlan, includeArchive: Bool, includeSettings: Bool, replacing: [UUID] = []) -> ImportResult {
        apply(plan, includeArchive: includeArchive, includeSettings: includeSettings, replacing: replacing, favicons: AppPaths.favicons)
    }
}
