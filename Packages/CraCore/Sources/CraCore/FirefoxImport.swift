import Foundation

// Firefox (and Zen, which is Firefox underneath): bookmarks from places.sqlite and open tabs from
// the session store, a mozLz4 file. Each app reads the SQLite file with its own SQLite (the Mac's
// libsqlite3, Windows' winsqlite3) and hands the rows here; the rest is the same on both.
// Saved logins come only through Firefox's own export (about:logins ▸ Export Passwords…).
public enum FirefoxImport {
    /// The session store, newest first: recovery.jsonlz4 while Firefox runs, sessionstore.jsonlz4
    /// after it quit, then the previous session's backup.
    public static let sessionFiles = ["sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4", "sessionstore-backups/previous.jsonlz4"]

    /// Every bookmark and folder with its page, in each folder's order.
    public static let bookmarksQuery = """
        SELECT b.id, b.type, b.parent, b.title, b.guid, b.dateAdded, p.url, p.title AS ptitle
        FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk = p.id ORDER BY b.parent, b.position
        """

    // MARK: profiles.ini

    /// The default profile from `root`'s profiles.ini: the [Install…] section's Default, else the
    /// [Profile…] marked Default=1, else the first, among those with a places.sqlite.
    public static func defaultProfile(root: URL) -> URL? {
        guard let ini = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return nil }
        return defaultProfile(ini: ini, root: root) {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("places.sqlite").path)
        }
    }

    /// `hasPlaces` says whether a profile folder holds a places.sqlite.
    public static func defaultProfile(ini: String, root: URL, hasPlaces: (URL) -> Bool) -> URL? {
        var sections: [(name: String, values: [String: String])] = []
        for raw in ini.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { sections.append((String(line.dropFirst().dropLast()), [:])) }
            else if let eq = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1].values[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        func resolve(_ path: String, relative: Bool) -> URL? {
            let u = relative ? root.appendingPathComponent(path, isDirectory: true) : URL(fileURLWithPath: path, isDirectory: true)
            return hasPlaces(u) ? u : nil
        }
        if let install = sections.first(where: { $0.name.hasPrefix("Install") }), let p = install.values["Default"],
           let u = resolve(p, relative: !isAbsolute(p)) { return u }
        let profiles = sections.filter { $0.name.hasPrefix("Profile") }
            .sorted { ($0.values["Default"] == "1") && !($1.values["Default"] == "1") }
        for s in profiles {
            if let p = s.values["Path"], let u = resolve(p, relative: s.values["IsRelative"] != "0") { return u }
        }
        return nil
    }

    /// "/Users/…" on the Mac; "C:\Users\…" or "\\server\…" on Windows.
    static func isAbsolute(_ path: String) -> Bool {
        let c = Array(path)
        return path.hasPrefix("/") || path.hasPrefix("\\") || (c.count >= 2 && c[1] == ":" && c[0].isLetter)
    }

    // MARK: Bookmarks

    /// The toolbar's bookmarks, then the menu's and the unsorted ones as folders, from
    /// `bookmarksQuery`'s rows (integers as Int64, text as String).
    public static func bookmarks(rows: [[String: Any]]) -> [ImportedItem] {
        var children: [Int64: [[String: Any]]] = [:]
        var idByGUID: [String: Int64] = [:]
        for r in rows {
            guard let id = r["id"] as? Int64 else { continue }
            if let g = r["guid"] as? String { idByGUID[g] = id }
            if let parent = r["parent"] as? Int64 { children[parent, default: []].append(r) }
        }
        var visited = Set<Int64>()
        func convert(_ r: [String: Any]) -> ImportedItem? {
            let title = r["title"] as? String ?? ""
            // dateAdded is µs since 1970.
            let created = (r["dateAdded"] as? Int64).map { Date(timeIntervalSince1970: Double($0) / 1_000_000) } ?? Date()
            switch r["type"] as? Int64 {
            case 1:
                guard let u = r["url"] as? String, u.hasPrefix("http") else { return nil }
                return ImportedItem(customTitle: title.isEmpty ? nil : title, pageTitle: title.isEmpty ? (r["ptitle"] as? String ?? "") : title,
                                    url: u, createdAt: created)
            case 2:
                // A folder inside itself (a damaged file) is read once.
                guard let id = r["id"] as? Int64, visited.insert(id).inserted else { return nil }
                let kids = (children[id] ?? []).compactMap(convert)
                return kids.isEmpty ? nil : ImportedItem(customTitle: title, pageTitle: title, url: nil, isFolder: true, children: kids, createdAt: created)
            default:
                return nil
            }
        }
        func items(_ guid: String) -> [ImportedItem] { idByGUID[guid].map { (children[$0] ?? []).compactMap(convert) } ?? [] }
        var out = items("toolbar_____")
        for (guid, name) in [("menu________", "Bookmarks Menu"), ("unfiled_____", "Other Bookmarks")] {
            let kids = items(guid)
            if !kids.isEmpty { out.append(ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true, children: kids)) }
        }
        return out
    }

    // MARK: Session store

    /// The first session file in `profile` that reads, as JSON.
    public static func session(profile: URL, files: [String] = sessionFiles) -> [String: Any]? {
        files.lazy.compactMap { json(profile.appendingPathComponent($0)) }.first
    }

    /// A mozLz4 file's JSON object.
    public static func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), let raw = mozLz4(data) else { return nil }
        return try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
    }

    /// The current page of every tab in every window.
    public static func openTabs(session: [String: Any]) -> [ImportedItem] {
        var out: [ImportedItem] = []
        for w in session["windows"] as? [[String: Any]] ?? [] {
            for t in w["tabs"] as? [[String: Any]] ?? [] {
                guard let entries = t["entries"] as? [[String: Any]], !entries.isEmpty else { continue }
                let index = min(max((t["index"] as? Int ?? entries.count) - 1, 0), entries.count - 1)
                guard let u = entries[index]["url"] as? String, u.hasPrefix("http") else { continue }
                out.append(ImportedItem(pageTitle: entries[index]["title"] as? String ?? "", url: u))
            }
        }
        return out
    }

    /// One space named for the browser: its bookmarks pinned, its open tabs in Today.
    public static func plan(browser: String, bookmarks: [ImportedItem], openTabs: [ImportedItem]) -> ImportPlan {
        var plan = ImportPlan(source: browser)
        var space = ImportedSpace(title: browser, emoji: "🦊", theme: nil)
        space.pinned = bookmarks
        space.today = openTabs
        if !space.pinned.isEmpty || !space.today.isEmpty { plan.spaces.append(space) }
        return plan
    }

    // MARK: mozLz4

    /// "mozLz40\0", the decompressed size (uint32, little-endian), one raw LZ4 block.
    public static func mozLz4(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes.prefix(8).elementsEqual(Array("mozLz40\0".utf8)) else { return nil }
        let size = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard size > 0, size < 512 << 20 else { return nil }
        return lz4Block(bytes[12...], size: size).map { Data($0) }
    }

    /// An LZ4 block (lz4's lz4_Block_format.md): sequences of a token, literals, a two-byte
    /// offset back into the output and a match length. nil unless it fills exactly `size` bytes.
    static func lz4Block(_ src: ArraySlice<UInt8>, size: Int) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(size)
        var i = src.startIndex
        func length(_ base: Int) -> Int? {
            var n = base
            guard base == 15 else { return n }
            while true {
                guard i < src.endIndex else { return nil }
                let b = src[i]
                i += 1
                n += Int(b)
                if b != 255 { return n }
            }
        }
        while i < src.endIndex {
            let token = src[i]
            i += 1
            guard let literals = length(Int(token >> 4)), literals <= src.endIndex - i, out.count + literals <= size else { return nil }
            out.append(contentsOf: src[i..<(i + literals)])
            i += literals
            // The last sequence is literals only.
            if i == src.endIndex { break }
            guard src.endIndex - i >= 2 else { return nil }
            let offset = Int(src[i]) | Int(src[i + 1]) << 8
            i += 2
            guard offset > 0, offset <= out.count, let extra = length(Int(token & 15)) else { return nil }
            let match = extra + 4
            guard out.count + match <= size else { return nil }
            let start = out.count - offset
            // The match may overlap what it writes (a run), so copy a byte at a time.
            for k in 0..<match { out.append(out[start + k]) }
        }
        return out.count == size ? out : nil
    }
}
