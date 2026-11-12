import AppKit

// The Mac's side of ChromiumImporter (CraCore reads bookmarks and sessions): history, favicons,
// and passwords and cookies decrypted with the browser's Keychain secret.

extension ChromiumImporter {
    // MARK: Top sites

    /// Most visited sites, one per host, for Dia's pinned-tabs step (rankedTopSitesTask).
    static func topSites(userData: URL, limit: Int) -> [TopSite] {
        var rows: [(url: String, title: String, visits: Int)] = []
        for p in profiles(userData: userData) {
            guard let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("History")) else { continue }
            for r in db.rows(TopSite.historyQuery) {
                guard let u = r["url"] as? String else { continue }
                rows.append((url: u, title: r["title"] as? String ?? "", visits: Int(r["visit_count"] as? Int64 ?? 0)))
            }
        }
        return TopSite.ranked(rows, limit: limit)
    }

    /// The largest cached icon for each host, from the profiles' Favicons
    /// databases (Dia imports Chromium favicons the same way).
    static func favicons(userData: URL, hosts: [String]) -> [String: NSImage] {
        var out: [String: NSImage] = [:]
        for p in profiles(userData: userData) {
            guard let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("Favicons")) else { continue }
            for host in hosts where out[host] == nil {
                let rows = db.rows(TopSite.faviconQuery(host: host))
                if let data = rows.first?["image_data"] as? Data, let img = NSImage(data: data) { out[host] = img }
            }
        }
        return out
    }

    // MARK: Passwords and cookies

    /// Decrypts each picked profile's cookies and saved logins with the
    /// browser's Keychain secret (one macOS password prompt per browser).
    static func credentials(browser: String, profiles: [ChromiumProfile], keychainService: String, keychainAccount: String,
                            cookies: Bool, passwords: Bool) throws -> ImportedCredentials {
        guard let secret = ChromiumCrypto.keychainSecret(service: keychainService, account: keychainAccount) else {
            throw CredentialImportError.keychainDenied(browser)
        }
        return try credentials(browser: browser, profiles: profiles, secret: secret, cookies: cookies, passwords: passwords)
    }

    /// The same with a secret already read (Dia's sidebar needs it too: one prompt for both).
    static func credentials(browser: String, profiles: [ChromiumProfile], secret: String,
                            cookies: Bool, passwords: Bool) throws -> ImportedCredentials {
        let key = ChromiumCrypto.key(fromSecret: secret)
        var out = ImportedCredentials()
        var readAny = false
        for p in profiles {
            if cookies, let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("Cookies"))
                ?? SQLiteSnapshot(copying: p.dir.appendingPathComponent("Network/Cookies")) {
                readAny = true
                out.cookies += readCookies(db, key: key).map { var c = $0; c.sourceProfile = p.id; return c }
            }
            if passwords, let db = SQLiteSnapshot(copying: p.dir.appendingPathComponent("Login Data")) {
                readAny = true
                out.logins += readLogins(db, key: key).map { var l = $0; l.sourceProfile = p.id; return l }
            }
        }
        if !readAny && (cookies || passwords) { throw CredentialImportError.unreadable(browser) }
        return out
    }

    private static func readCookies(_ db: SQLiteSnapshot, key: Data) -> [ImportedCookie] {
        let version = Int(db.scalar("SELECT value FROM meta WHERE key = 'version'") as? String ?? "") ?? 0
        let now = ChromiumTime.now
        let partitioned = db.columns(of: "cookies").contains("top_frame_site_key") ? "AND top_frame_site_key = ''" : ""
        return db.rows("SELECT host_key, name, value, encrypted_value, path, expires_utc, creation_utc, last_access_utc, is_secure, is_httponly, samesite FROM cookies WHERE (expires_utc = 0 OR expires_utc > \(now)) \(partitioned)").compactMap { r in
            guard let host = r["host_key"] as? String, let name = r["name"] as? String else { return nil }
            var value = r["value"] as? String ?? ""
            if value.isEmpty, let blob = r["encrypted_value"] as? Data, !blob.isEmpty {
                guard var plain = ChromiumCrypto.decrypt(blob, key: key) else { return nil }
                if version >= 24 {
                    // A wrong key can still unpad; the host digest proves the key was right.
                    guard plain.count >= 32, plain.prefix(32) == ChromiumCrypto.hostDigest(host) else { return nil }
                    plain = plain.dropFirst(32)
                }
                guard let s = String(data: plain, encoding: .utf8) else { return nil }
                value = s
            }
            return ImportedCookie(host: host, name: name, value: value, path: r["path"] as? String ?? "/",
                                  expires: r["expires_utc"] as? Int64 ?? 0, created: r["creation_utc"] as? Int64 ?? now,
                                  lastAccess: r["last_access_utc"] as? Int64 ?? now, secure: (r["is_secure"] as? Int64 ?? 0) != 0,
                                  httpOnly: (r["is_httponly"] as? Int64 ?? 0) != 0, sameSite: Int(r["samesite"] as? Int64 ?? -1))
        }
    }

    private static func readLogins(_ db: SQLiteSnapshot, key: Data) -> [ImportedLogin] {
        db.rows("SELECT origin_url, action_url, username_element, username_value, password_element, password_value, signon_realm, date_created FROM logins WHERE blacklisted_by_user = 0").compactMap { r in
            guard let blob = r["password_value"] as? Data, let plain = ChromiumCrypto.decrypt(blob, key: key),
                  let password = String(data: plain, encoding: .utf8), !password.isEmpty,
                  let realm = r["signon_realm"] as? String, let origin = r["origin_url"] as? String else { return nil }
            return ImportedLogin(originURL: origin, actionURL: r["action_url"] as? String ?? "",
                                 usernameElement: r["username_element"] as? String ?? "", username: r["username_value"] as? String ?? "",
                                 passwordElement: r["password_element"] as? String ?? "", password: password, signonRealm: realm,
                                 created: r["date_created"] as? Int64 ?? ChromiumTime.now)
        }
    }
}
