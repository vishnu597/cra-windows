import Foundation

/// The rows of Chromium's Login Data and Cookies databases, read from another browser and
/// written into Cra's profile, as plain dictionaries ([column: Int64 | Double | String | Data]) so
/// the SQLite side stays in each app. The values come sealed; `open` gives them back in the clear
/// (or nil for one that can't be read).
public enum ChromiumCredentialRows {
    /// Saved logins, without the sites the user said never to save.
    public static let loginsQuery = """
        SELECT origin_url, action_url, username_element, username_value, password_element, password_value, signon_realm, date_created \
        FROM logins WHERE blacklisted_by_user = 0
        """

    /// Cookies that haven't expired; only unpartitioned ones when the table has partitions.
    public static func cookiesQuery(now: Int64, partitioned: Bool) -> String {
        """
        SELECT host_key, name, value, encrypted_value, path, expires_utc, creation_utc, last_access_utc, is_secure, is_httponly, samesite \
        FROM cookies WHERE (expires_utc = 0 OR expires_utc > \(now))\(partitioned ? " AND top_frame_site_key = ''" : "")
        """
    }

    public static func login(_ row: [String: Any], open: (Data) -> Data?) -> ImportedLogin? {
        guard let sealed = row["password_value"] as? Data, let plain = open(sealed),
              let password = String(data: plain, encoding: .utf8), !password.isEmpty,
              let realm = row["signon_realm"] as? String, let origin = row["origin_url"] as? String else { return nil }
        return ImportedLogin(originURL: origin, actionURL: row["action_url"] as? String ?? "",
                             usernameElement: row["username_element"] as? String ?? "", username: row["username_value"] as? String ?? "",
                             passwordElement: row["password_element"] as? String ?? "", password: password, signonRealm: realm,
                             created: row["date_created"] as? Int64 ?? ChromiumTime.now)
    }

    /// A cookie, its value in `value` or sealed in `encrypted_value`; `open` gets the sealed bytes
    /// and the host (for the digest of a version 24 database).
    public static func cookie(_ row: [String: Any], now: Int64, open: (_ sealed: Data, _ host: String) -> String?) -> ImportedCookie? {
        guard let host = row["host_key"] as? String, let name = row["name"] as? String else { return nil }
        var value = row["value"] as? String ?? ""
        if value.isEmpty, let sealed = row["encrypted_value"] as? Data, !sealed.isEmpty {
            guard let plain = open(sealed, host) else { return nil }
            value = plain
        }
        return ImportedCookie(host: host, name: name, value: value, path: row["path"] as? String ?? "/",
                              expires: row["expires_utc"] as? Int64 ?? 0, created: row["creation_utc"] as? Int64 ?? now,
                              lastAccess: row["last_access_utc"] as? Int64 ?? now, secure: (row["is_secure"] as? Int64 ?? 0) != 0,
                              httpOnly: (row["is_httponly"] as? Int64 ?? 0) != 0, sameSite: Int(row["samesite"] as? Int64 ?? -1))
    }

    /// A Login Data row for `login`, its password already sealed for Cra's profile.
    public static func loginColumns(_ l: ImportedLogin, sealed: Data) -> [String: Any] {
        [
            "origin_url": l.originURL, "action_url": l.actionURL, "username_element": l.usernameElement,
            "username_value": l.username, "password_element": l.passwordElement, "password_value": sealed,
            "submit_element": "", "signon_realm": l.signonRealm, "date_created": l.created,
            "blacklisted_by_user": false, "scheme": Int64(0), "password_type": Int64(0), "times_used": Int64(0),
            "date_password_modified": l.created, "date_last_used": Int64(0),
        ]
    }

    /// A Cookies row for `cookie`, its value already sealed for Cra's profile. Chromium stores
    /// every unpartitioned cookie with has_cross_site_ancestor = 1 and matches on it when it
    /// updates or deletes one (the Mac's repairImportedCookies).
    public static func cookieColumns(_ c: ImportedCookie, sealed: Data) -> [String: Any] {
        [
            "creation_utc": c.created, "host_key": c.host, "top_frame_site_key": "", "name": c.name, "value": "",
            "encrypted_value": sealed, "path": c.path, "expires_utc": c.expires, "is_secure": c.secure,
            "is_httponly": c.httpOnly, "last_access_utc": c.lastAccess, "has_expires": c.expires > 0,
            "is_persistent": c.expires > 0, "priority": Int64(1), "samesite": Int64(c.sameSite),
            "source_scheme": Int64(c.secure ? 2 : 1), "source_port": Int64(c.secure ? 443 : 80),
            "last_update_utc": c.lastAccess, "source_type": Int64(0), "has_cross_site_ancestor": true,
        ]
    }

    /// A table's column, from `pragma_table_info`.
    public struct Column: Equatable {
        public var name: String
        public var type: String
        public var notNull: Bool
        public var hasDefault: Bool

        public init(name: String, type: String, notNull: Bool, hasDefault: Bool) {
            self.name = name
            self.type = type
            self.notNull = notNull
            self.hasDefault = hasDefault
        }

        /// From a `SELECT name, type, "notnull" AS nn, dflt_value FROM pragma_table_info(...)` row.
        public init?(row: [String: Any]) {
            guard let name = row["name"] as? String else { return nil }
            self.init(name: name, type: row["type"] as? String ?? "", notNull: (row["nn"] as? Int64) == 1, hasDefault: row["dflt_value"] != nil)
        }
    }

    /// The query `Column(row:)` reads.
    public static func columnsQuery(table: String) -> String {
        #"SELECT name, type, "notnull" AS nn, dflt_value FROM pragma_table_info('"# + table + "')"
    }

    /// `values` for the table's own columns: a column this Chromium doesn't have is left out, and
    /// one that is NOT NULL without a default and not given gets 0, an empty blob or "", so the
    /// insert keeps working across Chromium's schema versions.
    public static func fitted(_ values: [String: Any], to columns: [Column]) -> [(name: String, value: Any)] {
        var row: [String: Any] = [:]
        for column in columns {
            if let value = values[column.name] {
                row[column.name] = value
            } else if column.notNull && !column.hasDefault {
                let type = column.type.uppercased()
                row[column.name] = type.contains("INT") ? Int64(0) : (type.contains("BLOB") ? Data() : "")
            }
        }
        return row.keys.sorted().map { ($0, row[$0]!) }
    }
}
