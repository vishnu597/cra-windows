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
        return FirefoxImport.plan(browser: browser, bookmarks: bookmarks(profile: profile),
                                  openTabs: FirefoxImport.session(profile: profile).map(FirefoxImport.openTabs) ?? [])
    }

    /// The toolbar's bookmarks, then the menu and unsorted bookmarks as folders.
    static func bookmarks(profile: URL) -> [ImportedItem] {
        SQLiteSnapshot(copying: profile.appendingPathComponent("places.sqlite")).map { FirefoxImport.bookmarks(rows: $0.rows(FirefoxImport.bookmarksQuery)) } ?? []
    }

    /// The largest icon per host from favicons.sqlite.
    static func favicons(root: URL, hosts: [String]) -> [String: NSImage] {
        guard let profile = defaultProfile(root: root),
              let db = SQLiteSnapshot(copying: profile.appendingPathComponent("favicons.sqlite")) else { return [:] }
        var out: [String: NSImage] = [:]
        for host in hosts {
            let h = host.replacingOccurrences(of: "'", with: "")
            let rows = db.rows("""
                SELECT i.data FROM moz_icons i JOIN moz_icons_to_pages ip ON ip.icon_id = i.id JOIN moz_pages_w_icons p ON p.id = ip.page_id
                WHERE p.page_url LIKE 'https://\(h)/%' OR p.page_url LIKE 'https://www.\(h)/%' ORDER BY i.width DESC LIMIT 1
                """)
            if let data = rows.first?["data"] as? Data, let img = NSImage(data: data) { out[host] = img }
        }
        return out
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
