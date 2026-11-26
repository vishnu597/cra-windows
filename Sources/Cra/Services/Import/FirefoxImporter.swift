import AppKit

// Firefox (and Zen's bookmarks and favicons, see ZenImporter): bookmarks from places.sqlite and
// open tabs from the session store (mozLz4), read by CraCore's FirefoxImport. Saved logins come in only through
// Firefox's own export (about:logins ▸ Export Passwords…), read with
// PasswordCSV like Safari's exported Passwords.csv.

enum FirefoxImporter {
    /// The default profile from profiles.ini (CraCore's FirefoxImport, shared with Windows).
    static func defaultProfile(root: URL) -> URL? { FirefoxImport.defaultProfile(root: root) }

    static func plan(browser: String, root: URL) throws -> ImportPlan {
        guard let profile = defaultProfile(root: root) else { throw ImportError.notFound(browser) }
        var skipped: [ImportSkip] = []
        let marks = bookmarks(profile: profile, skip: { skipped.append($0) })
        let tabs = FirefoxImport.session(profile: profile, skip: { skipped.append($0) })
            .map { FirefoxImport.openTabs(session: $0, skip: { skipped.append($0) }) } ?? []
        var plan = FirefoxImport.plan(browser: browser, bookmarks: marks, openTabs: tabs, skipped: skipped)
        ImportFavicons.attach(to: &plan, folder: "cra-firefox-favicons", from: ImportSource.Kind.firefox.iconStores(dataDir: root))
        return plan
    }

    /// The toolbar's bookmarks, then the menu and unsorted bookmarks as folders. `skip` hears of each
    /// bookmark left out.
    static func bookmarks(profile: URL, skip: (ImportSkip) -> Void = { _ in }) -> [ImportedItem] {
        SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite"))
            .map { FirefoxImport.bookmarks(rows: $0.rows(FirefoxImport.bookmarksQuery), skip: skip) } ?? []
    }

    /// The current tab of every open window (CraCore's FirefoxImport). `skip` hears of each tab left out,
    /// or of a session store that could not be read.
    static func openTabs(profile: URL, skip: (ImportSkip) -> Void = { _ in }) -> [ImportedItem] {
        FirefoxImport.session(profile: profile, skip: skip).map { FirefoxImport.openTabs(session: $0, skip: skip) } ?? []
    }

    /// The largest icon per host from favicons.sqlite, read in one pass over its pages, which have no
    /// index on page_url.
    static func favicons(root: URL, hosts: [String]) -> [String: Data] {
        guard let profile = defaultProfile(root: root),
              let db = SQLiteSnapshot(copying: profile.appendingPathComponent("favicons.sqlite")) else { return [:] }
        var wanted: [String: [String]] = [:]
        for host in hosts { for name in ImportFavicons.names(of: host) { wanted[name, default: []].append(host) } }
        var best: [String: (icon: Int64, width: Int64)] = [:]
        for r in db.rows("SELECT p.page_url, i.id, i.width FROM moz_pages_w_icons p JOIN moz_icons_to_pages ip ON ip.page_id = p.id JOIN moz_icons i ON i.id = ip.icon_id") {
            guard let page = r["page_url"] as? String, let icon = r["id"] as? Int64, let width = r["width"] as? Int64,
                  let owners = ImportFavicons.webHost(page).flatMap({ wanted[$0] }) else { continue }
            for host in owners where width > best[host]?.width ?? -1 { best[host] = (icon, width) }
        }
        guard !best.isEmpty else { return [:] }
        let ids = Set(best.values.map(\.icon)).map(String.init).joined(separator: ",")
        var images: [Int64: Data] = [:]
        for r in db.rows("SELECT id, data FROM moz_icons WHERE id IN (\(ids))") {
            if let id = r["id"] as? Int64, let data = r["data"] as? Data { images[id] = data }
        }
        return best.compactMapValues { images[$0.icon] }
    }

    static func topSites(root: URL, limit: Int) -> [TopSite] {
        guard let profile = defaultProfile(root: root),
              let db = SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite")) else { return [] }
        var byHost: [String: TopSite] = [:]
        for r in db.rows("SELECT url, title, visit_count FROM moz_places WHERE hidden = 0 AND visit_count > 0 ORDER BY frecency DESC LIMIT 400") {
            guard let u = r["url"] as? String, let site = TopSite(url: u, title: r["title"] as? String ?? "", visits: Int(r["visit_count"] as? Int64 ?? 0)) else { continue }
            byHost[site.host, default: TopSite(host: site.host, url: site.url, title: site.title, visits: 0)].visits += site.visits
        }
        return Array(byHost.values.sorted { $0.visits > $1.visits }.prefix(limit))
    }
}

/// Exported password files: Firefox (url, username, password, …) and Safari
/// (Title, URL, Username, Password, Notes, OTPAuth). Columns are found by name.
enum PasswordCSV {
    static func logins(in text: String) -> [ImportedLogin] {
        var rows = parse(text)
        guard !rows.isEmpty else { return [] }
        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard let urlCol = header.firstIndex(where: { $0 == "url" || $0 == "origin" }),
              let userCol = header.firstIndex(where: { $0 == "username" || $0 == "login" }),
              let passCol = header.firstIndex(of: "password") else { return [] }
        return rows.compactMap { r in
            guard r.count > max(urlCol, userCol, passCol) else { return nil }
            return ImportedLogin(url: r[urlCol], username: r[userCol], password: r[passCol])
        }
    }

    /// RFC 4180: quoted fields may hold commas, quotes ("") and newlines.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var it = Array(text.unicodeScalars).makeIterator()
        var pending: Unicode.Scalar?
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { field.unicodeScalars.append("\"") } else { quoted = false; pending = n } }
                    else { quoted = false }
                } else { field.unicodeScalars.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r" {
                if c == "\r", let n = it.next(), n != "\n" { pending = n }
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else { field.unicodeScalars.append(c) }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
