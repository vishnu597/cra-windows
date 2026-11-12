import CraCEFWin
import CraCore
import Foundation

/// Passwords and sign-ins from another Chromium browser (the Mac's CredentialImport): read with
/// the browser's own key (Local State's, unwrapped with DPAPI), sealed again with Cra's, staged in
/// pending-credentials.json, and written into Cra's Login Data and Cookies on the next launch
/// before Chromium opens them (it keeps both locked while it runs). Chrome's app-bound cookies
/// ("v20") can't be read by anything but Chrome and stay there; ChromiumOSCrypt decides that.
enum CredentialImport {
    struct Result {
        var credentials = ImportedCredentials()
        var report = CredentialImportReport()
    }

    static var pendingFile: URL { WinPaths.supportDir.appendingPathComponent("pending-credentials.json") }

    // MARK: Reading another browser

    /// The saved logins and cookies of `profiles`, in the User Data folder `userData`.
    static func read(userData: URL, profiles: [ChromiumProfile]) -> Result {
        var result = Result()
        // Without a key only values from before Chrome 80 (DPAPI blobs of their own) open.
        let key = key(userData: userData) ?? Data()
        let now = ChromiumTime.now
        for profile in profiles {
            if let db = SQLiteSnapshot(copying: profile.dir.appendingPathComponent("Login Data")) {
                for row in db.rows(ChromiumCredentialRows.loginsQuery) {
                    let login = ChromiumCredentialRows.login(row) { sealed in
                        switch ChromiumOSCrypt.open(sealed, key: key, unprotect: unprotect) {
                        case .plain(let plain): return plain
                        case .locked: result.report.lockedPasswords += 1; return nil
                        case .failed: return nil
                        }
                    }
                    if var login {
                        login.sourceProfile = profile.id
                        result.credentials.logins.append(login)
                    }
                }
            }
            // Chromium on Windows keeps cookies under Network since 96. A browser that is running
            // holds the file shut, so it can't be copied.
            let cookies = [profile.dir.appendingPathComponent("Network/Cookies"), profile.dir.appendingPathComponent("Cookies")]
                .first { FileManager.default.fileExists(atPath: $0.path) }
            guard let cookies else { continue }
            guard let db = SQLiteSnapshot(copying: cookies) else {
                result.report.cookiesBusy = true
                continue
            }
            let version = Int(db.rows("SELECT value FROM meta WHERE key = 'version'").first?["value"] as? String ?? "") ?? 0
            let partitioned = db.columns(of: "cookies").contains { $0.name == "top_frame_site_key" }
            for row in db.rows(ChromiumCredentialRows.cookiesQuery(now: now, partitioned: partitioned)) {
                let cookie = ChromiumCredentialRows.cookie(row, now: now) { sealed, host in
                    switch ChromiumOSCrypt.open(sealed, key: key, unprotect: unprotect) {
                    case .plain(let plain): return ChromiumOSCrypt.cookieValue(plain, host: host, version: version)
                    case .locked: result.report.lockedSignIns += 1; return nil
                    case .failed: return nil
                    }
                }
                if var cookie {
                    cookie.sourceProfile = profile.id
                    result.credentials.cookies.append(cookie)
                }
            }
        }
        result.report.passwords = result.credentials.logins.count
        result.report.signIns = result.credentials.cookies.count
        return result
    }

    /// The AES key a User Data folder's values are sealed with (Cra's own too: its Chromium
    /// folder is one).
    static func key(userData: URL) -> Data? {
        guard let state = try? Data(contentsOf: userData.appendingPathComponent("Local State")),
              let wrapped = ChromiumOSCrypt.wrappedKey(localState: state) else { return nil }
        return unprotect(wrapped)
    }

    static func unprotect(_ data: Data) -> Data? {
        data.withUnsafeBytes { raw -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var length = 0
            guard let out = cra_dpapi_unprotect(base, raw.count, &length) else { return nil }
            defer { cra_data_free(out) }
            return Data(bytes: out, count: length)
        }
    }

    // MARK: Staging

    /// Adds `credentials` to what is staged, sealed with Cra's key, each row for the Cra profile
    /// `profiles` maps its source profile to. False when nothing could be written.
    static func stage(_ credentials: ImportedCredentials, profiles: ImportProfileMap) -> Bool {
        guard !credentials.isEmpty else { return true }
        guard let key = key(userData: WinPaths.chromiumCache) else { return false }
        var pending = loadPending() ?? PendingCredentials()
        guard pending.add(credentials, profiles: profiles, seal: { ChromiumOSCrypt.seal($0, key: key) }) else { return false }
        return save(pending)
    }

    private static func loadPending() -> PendingCredentials? {
        (try? Data(contentsOf: pendingFile)).flatMap { try? JSONDecoder().decode(PendingCredentials.self, from: $0) }
    }

    private static func save(_ pending: PendingCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(pending) else { return false }
        return (try? data.write(to: pendingFile, options: .atomic)) != nil
    }

    // MARK: Applying

    /// Called before Chromium starts, with Cra's Chromium folder. A profile Chromium has not made
    /// a database for yet gets one with Default's schema, so its spaces are signed in from their
    /// first page. Rows stay in the file while their profile's databases are missing (no first
    /// run yet) or busy (another Cra has them open).
    static func applyPending(root: URL) {
        guard FileManager.default.fileExists(atPath: pendingFile.path), var pending = loadPending(),
              let key = key(userData: root) else { return }
        let template = root.appendingPathComponent("Default", isDirectory: true)
        for folder in pending.folders {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            let cookies = pending.cookies(in: folder), logins = pending.logins(in: folder)
            let cookiesDB = database(dir, "Cookies", template: template), loginsDB = database(dir, "Login Data", template: template)
            let cookiesOK = cookies.isEmpty || insertCookies(cookies, into: cookiesDB, key: key)
            let loginsOK = logins.isEmpty || insertLogins(logins, into: loginsDB)
            pending.remove(folder: folder, cookies: cookiesOK, logins: loginsOK)
            if !cookiesOK || !loginsOK {
                NSLog("Cra: imported passwords/sign-ins for \(folder) stay pending (cookies \(cookiesOK), logins \(loginsOK))")
            }
        }
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: pendingFile)
        } else {
            _ = save(pending)
        }
    }

    /// Where a profile's `name` database is: under Network (cookies, since Chromium 96) or in the
    /// profile's folder; made from Default's when the profile has none yet.
    private static func database(_ dir: URL, _ name: String, template: URL) -> URL {
        let candidates = name == "Cookies" ? ["Network/\(name)", name] : [name]
        for candidate in candidates where FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            return dir.appendingPathComponent(candidate)
        }
        let source = candidates.first { FileManager.default.fileExists(atPath: template.appendingPathComponent($0).path) } ?? candidates[0]
        let url = dir.appendingPathComponent(source)
        if dir.standardizedFileURL != template.standardizedFileURL {
            createDatabase(url, like: template.appendingPathComponent(source))
        }
        return url
    }

    /// An empty database with `template`'s tables, indexes and meta rows (Chromium's schema
    /// version), for a profile Chromium has not opened yet. Nothing when `url` exists.
    private static func createDatabase(_ url: URL, like template: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), let source = SQLiteDatabase(url: template) else { return }
        let schema = source.rows("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type = 'table' DESC, rowid")
            .compactMap { $0["sql"] as? String }
        let meta = source.rows("SELECT key, value FROM meta")
        guard !schema.isEmpty, !meta.isEmpty else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).creating")
        try? fm.removeItem(at: staging)
        var ok = false
        if let db = SQLiteDatabase(url: staging, create: true) {
            ok = db.transaction {
                for sql in schema where !db.exec(sql) { return false }
                for row in meta {
                    guard let k = row["key"] as? String else { return false }
                    if !db.insert(into: "meta", ["key": k, "value": row["value"] ?? ""], orIgnore: false) { return false }
                }
                return true
            }
        }
        guard ok else { try? fm.removeItem(at: staging); return }
        try? fm.moveItem(at: staging, to: url)
    }

    private static func insertCookies(_ cookies: [PendingCredentials.Cookie], into url: URL, key: Data) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path), let db = SQLiteDatabase(url: url) else { return false }
        let version = Int(db.rows("SELECT value FROM meta WHERE key = 'version'").first?["value"] as? String ?? "") ?? 0
        return db.transaction {
            for p in cookies {
                guard case .plain(let plain) = ChromiumOSCrypt.open(p.encrypted, key: key, unprotect: unprotect),
                      let value = String(data: plain, encoding: .utf8),
                      let sealed = ChromiumOSCrypt.seal(ChromiumOSCrypt.cookiePlaintext(value, host: p.c.host, version: version), key: key)
                else { continue }  // sealed with a key Cra no longer has: nothing to bring
                if !db.insert(into: "cookies", ChromiumCredentialRows.cookieColumns(p.c, sealed: sealed), orIgnore: true) { return false }
            }
            return true
        }
    }

    private static func insertLogins(_ logins: [PendingCredentials.Login], into url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path), let db = SQLiteDatabase(url: url) else { return false }
        return db.transaction {
            for p in logins {
                // A login already saved in Cra for the same site and user wins.
                let exists = db.rows("SELECT 1 FROM logins WHERE signon_realm = ? AND username_value = ? LIMIT 1", [p.l.signonRealm, p.l.username])
                if !exists.isEmpty { continue }
                if !db.insert(into: "logins", ChromiumCredentialRows.loginColumns(p.l, sealed: p.encrypted), orIgnore: true) { return false }
            }
            return true
        }
    }
}

// MARK: - SQLite

/// A database through CraCEFWin's SQLite (Windows' winsqlite3). Rows come as
/// [column: Int64 | Double | String | Data]; NULLs are left out.
final class SQLiteDatabase {
    private let db: OpaquePointer
    private var closed = false

    init?(url: URL, create: Bool = false) {
        // Windows' own spelling of the path (backslashes), in UTF-8 as SQLite takes it.
        guard let db = url.withUnsafeFileSystemRepresentation({ path in path.flatMap { cra_sqlite_open($0, create ? 1 : 0) } }) else { return nil }
        self.db = db
    }

    deinit { close() }

    func close() {
        guard !closed else { return }
        closed = true
        cra_sqlite_close(db)
    }

    func exec(_ sql: String) -> Bool { cra_sqlite_exec(db, sql) == 1 }

    func rows(_ sql: String, _ values: [Any?] = []) -> [[String: Any]] {
        guard let statement = cra_sqlite_prepare(db, sql) else { return [] }
        defer { cra_sqlite_finalize(statement) }
        guard bind(statement, values) else { return [] }
        var out: [[String: Any]] = []
        while cra_sqlite_step(statement) == 1 {
            var row: [String: Any] = [:]
            for i in 0..<cra_sqlite_column_count(statement) {
                guard let name = cra_sqlite_column_name(statement, i).map({ String(cString: $0) }) else { continue }
                switch cra_sqlite_column_type(statement, i) {
                case 1: row[name] = cra_sqlite_column_int64(statement, i)
                case 2: row[name] = cra_sqlite_column_double(statement, i)
                case 3: row[name] = cra_sqlite_column_text(statement, i).map { String(cString: $0) } ?? ""
                case 4:
                    let n = Int(cra_sqlite_column_bytes(statement, i))
                    row[name] = n > 0 ? cra_sqlite_column_blob(statement, i).map { Data(bytes: $0, count: n) } ?? Data() : Data()
                default: break
                }
            }
            out.append(row)
        }
        return out
    }

    func columns(of table: String) -> [ChromiumCredentialRows.Column] {
        rows(ChromiumCredentialRows.columnsQuery(table: table)).compactMap(ChromiumCredentialRows.Column.init(row:))
    }

    /// `values` fitted to the table's columns (ChromiumCredentialRows.fitted).
    func insert(into table: String, _ values: [String: Any], orIgnore: Bool) -> Bool {
        let row = ChromiumCredentialRows.fitted(values, to: columns(of: table))
        guard !row.isEmpty else { return false }
        let names = row.map(\.name)
        let sql = "INSERT \(orIgnore ? "OR IGNORE " : "")INTO \(table) (\(names.joined(separator: ","))) VALUES (\(names.map { _ in "?" }.joined(separator: ",")))"
        guard let statement = cra_sqlite_prepare(db, sql) else { return false }
        defer { cra_sqlite_finalize(statement) }
        return bind(statement, row.map(\.value)) && cra_sqlite_step(statement) == 0
    }

    func transaction(_ body: () -> Bool) -> Bool {
        guard exec("BEGIN IMMEDIATE") else { return false }
        if body() { return exec("COMMIT") }
        _ = exec("ROLLBACK")
        return false
    }

    /// Binds Int64, Int, Bool, Double, String and Data; anything else is NULL.
    private func bind(_ statement: OpaquePointer, _ values: [Any?]) -> Bool {
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            let ok: Int32
            switch value {
            case let x as Int64: ok = cra_sqlite_bind_int64(statement, index, x)
            case let x as Int: ok = cra_sqlite_bind_int64(statement, index, Int64(x))
            case let x as Bool: ok = cra_sqlite_bind_int64(statement, index, x ? 1 : 0)
            case let x as Double: ok = cra_sqlite_bind_double(statement, index, x)
            case let x as String: ok = cra_sqlite_bind_text(statement, index, x)
            case let x as Data: ok = x.withUnsafeBytes { cra_sqlite_bind_blob(statement, index, $0.baseAddress, Int32($0.count)) }
            default: ok = cra_sqlite_bind_null(statement, index)
            }
            if ok != 1 { return false }
        }
        return true
    }
}

/// A read-only look at a database another app may hold open: the file and its -wal, -shm and
/// -journal are copied to a temporary folder first, so the read never touches (or waits on) the
/// original. nil when the file can't be copied, as when its browser holds it shut.
final class SQLiteSnapshot {
    private let database: SQLiteDatabase
    private let dir: URL

    init?(copying url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let dir = fm.temporaryDirectory.appendingPathComponent("cra-import-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm", "-journal"] where fm.fileExists(atPath: url.path + suffix) {
                try fm.copyItem(atPath: url.path + suffix, toPath: dir.appendingPathComponent(url.lastPathComponent + suffix).path)
            }
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
        guard let database = SQLiteDatabase(url: dir.appendingPathComponent(url.lastPathComponent)) else {
            try? fm.removeItem(at: dir)
            return nil
        }
        self.database = database
        self.dir = dir
    }

    deinit {
        database.close()
        try? FileManager.default.removeItem(at: dir)
    }

    func rows(_ sql: String) -> [[String: Any]] { database.rows(sql) }
    func columns(of table: String) -> [ChromiumCredentialRows.Column] { database.columns(of: table) }
}
