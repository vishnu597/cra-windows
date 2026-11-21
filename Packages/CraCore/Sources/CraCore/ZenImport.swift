import Foundation

// Zen is Firefox with Arc's sidebar: spaces, Essentials, pinned tabs and folders.
// Since Zen 1.15 one file holds that sidebar for every window,
// <profile>/zen-sessions.jsonlz4 = {spaces, tabs, folders, groups, splitViewData}
// (src/zen/sessionstore/ZenSessionManager.sys.mjs, read against 1.23.4b). Older
// profiles keep spaces in places.sqlite (zen_workspaces) and the tabs, with the
// same zen* fields, in Firefox's session store. Favicons stay with each app.
public enum ZenImport {
    /// Zen's own session file, then its backup.
    public static let sessionFiles = ["zen-sessions.jsonlz4", "zen-sessions-backup/clean.jsonlz4"]

    /// Older Zen's spaces table in places.sqlite.
    public static let workspacesQuery = "SELECT * FROM zen_workspaces ORDER BY position"

    public struct Sidebar {
        public var spaces: [[String: Any]]
        public var tabs: [[String: Any]]
        public var folders: [[String: Any]]

        public init(spaces: [[String: Any]], tabs: [[String: Any]], folders: [[String: Any]]) {
            self.spaces = spaces
            self.tabs = tabs
            self.folders = folders
        }
    }

    /// The sidebar from `profile`: Zen's own session file, else Firefox's session store with the
    /// spaces of older Zen versions (`workspaces` reads `workspacesQuery` from places.sqlite).
    public static func sidebar(profile: URL, workspaces: () -> [[String: Any]]) -> Sidebar {
        sidebar(zenSessions: sessionFiles.lazy.compactMap { FirefoxImport.json(profile.appendingPathComponent($0)) }.first(where: hasSpaces),
                sessionStore: FirefoxImport.session(profile: profile), workspaces: workspaces)
    }

    static func hasSpaces(_ root: [String: Any]) -> Bool { !(root["spaces"] as? [[String: Any]] ?? []).isEmpty }

    public static func sidebar(zenSessions: [String: Any]?, sessionStore: [String: Any]?, workspaces: () -> [[String: Any]]) -> Sidebar {
        if let root = zenSessions, let spaces = root["spaces"] as? [[String: Any]], !spaces.isEmpty {
            return Sidebar(spaces: spaces, tabs: root["tabs"] as? [[String: Any]] ?? [], folders: root["folders"] as? [[String: Any]] ?? [])
        }
        let windows = sessionStore?["windows"] as? [[String: Any]] ?? []
        // Every window holds the pinned tabs; keep one copy of each.
        var seen = Set<String>()
        let tabs = windows.flatMap { $0["tabs"] as? [[String: Any]] ?? [] }.filter { t in
            guard let id = (t["zenSyncId"] ?? t["zenPinnedId"]) as? String else { return true }
            return seen.insert(id).inserted
        }
        var spaces = windows.first?["spaces"] as? [[String: Any]] ?? []
        if spaces.isEmpty {
            spaces = workspaces().map { r in
                var s: [String: Any] = ["uuid": r["uuid"] as? String ?? "", "name": r["name"] as? String ?? "",
                                        "icon": r["icon"] as? String ?? "", "position": Double(r["position"] as? Int64 ?? 0)]
                if let colors = (r["theme_colors"] as? String).flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) }) {
                    s["theme"] = ["gradientColors": colors, "opacity": r["theme_opacity"] as? Double ?? 0.5,
                                  "texture": r["theme_texture"] as? Double ?? 0]
                }
                return s
            }
        }
        return Sidebar(spaces: spaces, tabs: tabs, folders: windows.first?["folders"] as? [[String: Any]] ?? [])
    }

    /// Spaces in Zen's order, Essentials as every space's favorites, pinned tabs in their folders,
    /// the rest in Today, and Firefox's bookmarks in a Bookmarks folder of the first space.
    /// `favicons` adds icons to the spaces before empty ones are dropped.
    public static func plan(sidebar: Sidebar, bookmarks: [ImportedItem],
                            favicons: (inout [ImportedSpace]) -> Void = { _ in }) -> ImportPlan {
        var plan = ImportPlan(source: "Zen")
        let spaceData = sidebar.spaces.sorted { ($0["position"] as? Double ?? 0) < ($1["position"] as? Double ?? 0) }
        var spaces = spaceData.map { s -> ImportedSpace in
            let icon = s["icon"] as? String ?? ""
            // Zen's icon is an emoji or a chrome://…svg path.
            let emoji = icon.isEmpty || icon.contains("/") ? "🗂️" : icon
            return ImportedSpace(title: (s["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space", emoji: emoji,
                                 theme: theme(s["theme"] as? [String: Any]))
        }
        if spaces.isEmpty { spaces = [ImportedSpace(title: "Zen", emoji: "🗂️", theme: nil)] }
        let spaceIndex = Dictionary(spaceData.enumerated().compactMap { i, s in (s["uuid"] as? String).map { ($0, i) } },
                                    uniquingKeysWith: { a, _ in a })

        // Folders nest through parentId; split views are groups inside a folder and flatten into it.
        var folders: [String: (name: String, parent: String?, split: Bool)] = [:]
        for f in sidebar.folders {
            guard let id = f["id"] as? String else { continue }
            folders[id] = (f["name"] as? String ?? "Folder", f["parentId"] as? String, f["splitViewGroup"] as? Bool ?? false)
        }
        func folderChain(_ groupID: String?) -> [String] {
            var chain: [String] = [], id = groupID
            while let g = id, let f = folders[g], !chain.contains(g) {
                if !f.split { chain.insert(g, at: 0) }
                id = f.parent
            }
            return chain
        }

        var essentials: [ImportedItem] = []
        // Per space: pinned and Today trees, built in the session's tab order.
        let trees = spaces.map { _ in (pinned: ImportTree(), today: ImportTree()) }
        for t in sidebar.tabs {
            guard let item = tabItem(t) else { continue }
            if flag(t["zenEssential"]) {
                if !essentials.contains(where: { $0.url == item.url }) { essentials.append(item) }
                continue
            }
            let i = (t["zenWorkspace"] as? String).flatMap { spaceIndex[$0] } ?? 0
            let chain = folderChain(t["groupId"] as? String)
            if flag(t["pinned"]) || !chain.isEmpty {
                trees[i].pinned.insert(item, path: chain.map { ($0, folders[$0]!.name) })
            } else {
                trees[i].today.insert(item, path: [])
            }
        }

        // Essentials sit above every space in Zen; Cra's favorites belong to a space.
        for i in spaces.indices {
            spaces[i].favorites = essentials
            spaces[i].pinned = trees[i].pinned.items
            spaces[i].today = trees[i].today.items
        }
        if !bookmarks.isEmpty {
            spaces[0].pinned.append(ImportedItem(customTitle: "Bookmarks", pageTitle: "Bookmarks", url: nil, isFolder: true, children: bookmarks))
        }
        favicons(&spaces)
        plan.spaces = spaces.filter { !$0.favorites.isEmpty || !$0.pinned.isEmpty || !$0.today.isEmpty }
        return plan
    }

    /// Older Zen wrote some flags as the strings "true"/"false".
    static func flag(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? String) == "true") }

    /// A pinned tab keeps the URL it was pinned with (Arc's savedURL), not where it navigated.
    static func tabItem(_ t: [String: Any]) -> ImportedItem? {
        if flag(t["zenIsEmpty"]) || flag(t["zenIsGlance"]) { return nil }
        let entries = t["entries"] as? [[String: Any]] ?? []
        let current = entries.isEmpty ? nil : entries[min(max((t["index"] as? Int ?? entries.count) - 1, 0), entries.count - 1)]
        let home = (t["_zenPinnedInitialState"] as? [String: Any])?["entry"] as? [String: Any]
        let entry = (flag(t["pinned"]) || flag(t["zenEssential"]) ? home : nil) ?? current
        guard let url = entry?["url"] as? String, url.hasPrefix("http") else { return nil }
        let label = (t["zenStaticLabel"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = (entry?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? current?["title"] as? String ?? ""
        return ImportedItem(customTitle: label, pageTitle: title, url: url)
    }

    /// Zen's gradient: up to three dots ({c: [r, g, b]} or a CSS colour when custom),
    /// laid over the window at `opacity`, with `texture` grain.
    static func theme(_ t: [String: Any]?) -> SpaceTheme? {
        guard let t, let dots = t["gradientColors"] as? [[String: Any]] else { return nil }
        let colors: [String] = dots.compactMap { d in
            if let c = d["c"] as? [Double], c.count >= 3 {
                return String(format: "#%02X%02X%02X", Int(c[0].rounded()), Int(c[1].rounded()), Int(c[2].rounded()))
            }
            if let s = d["c"] as? String, HexColor.components(s) != nil { return s.uppercased() }
            return nil
        }
        guard let first = colors.first else { return nil }
        let opacity = t["opacity"] as? Double ?? 0.5
        return SpaceTheme(colors: Array((colors + [first]).prefix(2)), intensity: max(0.3, min(1, opacity)),
                          noise: max(0, min(1, t["texture"] as? Double ?? 0)), appearance: "auto", accent: first)
    }
}
