import Foundation

// Chrome, Brave, Edge, Vivaldi, Opera, Chromium and Helium (and Arc's and Dia's own Chromium
// profiles for passwords and cookies). Each profile becomes a space with its bookmarks bar pinned
// and its last session's tabs in Today. The files are the same on the Mac and on Windows; the
// apps say where each browser's User Data is. Passwords, cookies, history and favicons (SQLite,
// the Keychain or DPAPI) stay in the apps.

public struct ChromiumProfile: Identifiable, Hashable {
    /// Folder name: "Default", "Profile 1".
    public let id: String
    /// Shown name from Local State.
    public let name: String
    public let dir: URL

    public init(id: String, name: String, dir: URL) {
        self.id = id
        self.name = name
        self.dir = dir
    }
}

public enum ChromiumImporter {
    /// Profile folders under a "User Data" root, named as the browser shows them.
    /// Opera keeps its single profile in the root itself.
    public static func profiles(userData: URL) -> [ChromiumProfile] {
        let fm = FileManager.default
        let names = profileNames(userData: userData)
        let dirs = ((try? fm.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted(by: profileOrder)
        var out = dirs.compactMap { d -> ChromiumProfile? in
            let dir = userData.appendingPathComponent(d, isDirectory: true)
            guard hasData(dir) else { return nil }
            return ChromiumProfile(id: d, name: names[d] ?? (d == "Default" ? "Default" : d), dir: dir)
        }
        if out.isEmpty && hasData(userData) { out = [ChromiumProfile(id: "Default", name: "Default", dir: userData)] }
        return out
    }

    /// Default first, then "Profile 2" before "Profile 10".
    static func profileOrder(_ a: String, _ b: String) -> Bool {
        if a == "Default" || b == "Default" { return a == "Default" && b != "Default" }
        let na = Int(a.dropFirst("Profile ".count)), nb = Int(b.dropFirst("Profile ".count))
        if let na, let nb, na != nb { return na < nb }
        return a < b
    }

    /// Local State's profile.info_cache: the name the browser shows for each profile folder.
    public static func profileNames(userData: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: userData.appendingPathComponent("Local State")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }

    static func hasData(_ dir: URL) -> Bool {
        ["Bookmarks", "History", "Cookies", "Login Data"].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
    }

    // MARK: Plan

    public static func plan(browser: String, userData: URL) throws -> ImportPlan {
        try plan(browser: browser, profiles: profiles(userData: userData))
    }

    /// The plan for the profiles picked: one space each, named after the browser (and the
    /// profile, when there are several).
    public static func plan(browser: String, profiles: [ChromiumProfile]) throws -> ImportPlan {
        guard !profiles.isEmpty else { throw ImportError.notFound(browser) }
        var plan = ImportPlan(source: browser)
        for p in profiles {
            let title = profiles.count == 1 ? browser : "\(browser) · \(p.name)"
            var space = ImportedSpace(title: title, emoji: "🌐", theme: nil)
            let bm = bookmarks(profile: p.dir)
            space.pinned = bm.bar + (bm.other.isEmpty ? [] : [ImportedItem(customTitle: "Other Bookmarks", pageTitle: "Other Bookmarks", url: nil, isFolder: true, children: bm.other)])
            space.today = openTabs(profile: p.dir)
            if !space.pinned.isEmpty || !space.today.isEmpty { plan.spaces.append(space) }
        }
        return plan
    }

    public static func bookmarks(profile dir: URL) -> (bar: [ImportedItem], other: [ImportedItem]) {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("Bookmarks")) else { return ([], []) }
        return bookmarks(data)
    }

    /// A Bookmarks file's bar, and its Other and Mobile (synced) bookmarks.
    public static func bookmarks(_ data: Data) -> (bar: [ImportedItem], other: [ImportedItem]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return ([], []) }
        func convert(_ node: [String: Any]) -> ImportedItem? {
            let name = node["name"] as? String ?? ""
            let created = (node["date_added"] as? String).flatMap(Int64.init).map(ChromiumTime.date) ?? Date()
            if node["type"] as? String == "url", let u = node["url"] as? String, u.hasPrefix("http") {
                return ImportedItem(customTitle: name.isEmpty ? nil : name, pageTitle: name, url: u, createdAt: created)
            }
            if node["type"] as? String == "folder" {
                let kids = (node["children"] as? [[String: Any]] ?? []).compactMap(convert)
                return kids.isEmpty ? nil : ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids, createdAt: created)
            }
            return nil
        }
        func children(_ key: String) -> [ImportedItem] {
            ((roots[key] as? [String: Any])?["children"] as? [[String: Any]] ?? []).compactMap(convert)
        }
        return (children("bookmark_bar"), children("other") + children("synced"))
    }

    public static func date(_ chromiumMicros: Int64) -> Date { ChromiumTime.date(chromiumMicros) }

    // MARK: Session (SNSS)

    /// The tabs of the last session, from the newest Sessions/Session_* file
    /// (older Chromium: "Current Session"). Commands are
    /// `uint16 size, uint8 id, payload`; ids from session_service_commands.cc.
    public static func openTabs(profile dir: URL) -> [ImportedItem] {
        let fm = FileManager.default
        let sessions = dir.appendingPathComponent("Sessions", isDirectory: true)
        func modified(_ url: URL) -> Date {
            ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
        }
        let candidates = ((try? fm.contentsOfDirectory(atPath: sessions.path)) ?? [])
            .filter { $0.hasPrefix("Session_") }
            .map { sessions.appendingPathComponent($0) }
            .sorted { modified($0) > modified($1) }
        let file = candidates.first ?? dir.appendingPathComponent("Current Session")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return parseSession(data)
    }

    public static func parseSession(_ data: Data) -> [ImportedItem] {
        let b = [UInt8](data)
        guard b.count > 8, b[0] == 0x53, b[1] == 0x4E, b[2] == 0x53, b[3] == 0x53 else { return [] }
        let version = le32(b, 4)
        guard version == 1 || version == 3 else { return [] }   // 2 and 4 are encrypted
        struct Tab { var window: Int32 = 0; var index: Int32 = 0; var selected: Int32 = -1; var navs: [Int32: (String, String)] = [:] }
        var tabs: [Int32: Tab] = [:], closedTabs = Set<Int32>(), closedWindows = Set<Int32>()
        var p = 8
        while p + 3 <= b.count {
            let size = Int(UInt16(b[p]) | UInt16(b[p + 1]) << 8)
            guard size >= 1, p + 2 + size <= b.count else { break }
            let id = b[p + 2]
            let body = Array(b[(p + 3)..<(p + 2 + size)])
            p += 2 + size
            switch id {
            case 0 where body.count >= 8:   // SetTabWindow {window, tab}
                tabs[le32s(body, 4), default: Tab()].window = le32s(body, 0)
            case 2 where body.count >= 8:   // SetTabIndexInWindow {tab, index}
                tabs[le32s(body, 0), default: Tab()].index = le32s(body, 4)
            case 6:                         // UpdateTabNavigation (pickle)
                var r = PickleReader(body)
                guard let tab = r.int32(), let idx = r.int32(), let url = r.string() else { continue }
                let title = r.string16() ?? ""
                tabs[tab, default: Tab()].navs[idx] = (url, title)
            case 7 where body.count >= 8:   // SetSelectedNavigationIndex {tab, index}
                tabs[le32s(body, 0), default: Tab()].selected = le32s(body, 4)
            case 16 where body.count >= 4:  // TabClosed
                closedTabs.insert(le32s(body, 0))
            case 17 where body.count >= 4:  // WindowClosed
                closedWindows.insert(le32s(body, 0))
            default: break
            }
        }
        return tabs.filter { !closedTabs.contains($0.key) && !closedWindows.contains($0.value.window) }
            .sorted { ($0.value.window, $0.value.index) < ($1.value.window, $1.value.index) }
            .compactMap { _, t -> ImportedItem? in
                guard let nav = t.navs[t.selected] ?? t.navs.max(by: { $0.key < $1.key })?.value, nav.0.hasPrefix("http") else { return nil }
                return ImportedItem(pageTitle: nav.1, url: nav.0)
            }
    }

    static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    static func le32s(_ b: [UInt8], _ i: Int) -> Int32 { Int32(bitPattern: le32(b, i)) }

    /// base::Pickle: uint32 payload size, then 4-byte aligned fields.
    struct PickleReader {
        let b: [UInt8]
        var p = 4
        init(_ b: [UInt8]) { self.b = b }
        mutating func int32() -> Int32? {
            guard p + 4 <= b.count else { return nil }
            defer { p += 4 }
            return ChromiumImporter.le32s(b, p)
        }
        mutating func string() -> String? {
            guard let n = int32(), n >= 0, p + Int(n) <= b.count else { return nil }
            defer { p += (Int(n) + 3) & ~3 }
            return String(decoding: b[p..<(p + Int(n))], as: UTF8.self)
        }
        mutating func string16() -> String? {
            guard let n = int32(), n >= 0, p + Int(n) * 2 <= b.count else { return nil }
            let units = stride(from: p, to: p + Int(n) * 2, by: 2).map { UInt16(b[$0]) | UInt16(b[$0 + 1]) << 8 }
            p += (Int(n) * 2 + 3) & ~3
            return String(decoding: units, as: UTF16.self)
        }
    }
}

/// A frequently visited site, for suggestions on the pinned tabs step.
public struct TopSite: Hashable {
    public var host: String
    public var url: String
    public var title: String
    public var visits: Int

    public init(host: String, url: String, title: String, visits: Int) {
        self.host = host; self.url = url; self.title = title; self.visits = visits
    }

    /// Reduced to the site's front page; nil for non-web URLs and search results.
    public init?(url: String, title: String, visits: Int) {
        guard let u = URL(string: url), let scheme = u.scheme, scheme.hasPrefix("http"), var host = u.host else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let skip = ["google.", "bing.com", "duckduckgo.com", "localhost", "127.0.0.1", "accounts.", "login.", "auth."]
        if skip.contains(where: { host.hasPrefix($0) }) { return nil }
        self.host = host
        self.url = "https://\(u.host ?? host)/"
        self.title = title
        self.visits = visits
    }
}
