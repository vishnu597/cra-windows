import Foundation

// Passwords and cookies read from another browser (Dia's "Unlock your data for import"). Each
// app reads them with its platform's crypto (the Mac's Keychain secret, Windows' DPAPI key) and
// stages them for Cra's Chromium profile (PendingCredentials).

public struct ImportedCookie: Codable, Equatable {
    public var host: String            // host_key: ".example.com" for domain cookies
    public var name: String
    public var value: String
    public var path: String
    /// Chromium time (µs since 1601); 0 for a session cookie.
    public var expires: Int64
    public var created: Int64
    public var lastAccess: Int64
    public var secure: Bool
    public var httpOnly: Bool
    /// Chromium CookieSameSite: -1 unspecified, 0 none, 1 lax, 2 strict.
    public var sameSite: Int
    /// The source browser's profile folder it was read from.
    public var sourceProfile: String?

    public init(host: String, name: String, value: String, path: String, expires: Int64, created: Int64, lastAccess: Int64,
                secure: Bool, httpOnly: Bool, sameSite: Int, sourceProfile: String? = nil) {
        self.host = host; self.name = name; self.value = value; self.path = path; self.expires = expires
        self.created = created; self.lastAccess = lastAccess; self.secure = secure; self.httpOnly = httpOnly
        self.sameSite = sameSite; self.sourceProfile = sourceProfile
    }
}

public struct ImportedLogin: Codable, Equatable {
    public var originURL: String
    public var actionURL: String = ""
    public var usernameElement: String = ""
    public var username: String
    public var passwordElement: String = ""
    public var password: String
    public var signonRealm: String
    public var created: Int64
    /// The source browser's profile folder it was read from.
    public var sourceProfile: String?

    /// A login from a CSV or Firefox: the realm is the page's origin.
    public init?(url: String, username: String, password: String, created: Int64 = ChromiumTime.now) {
        guard let u = URL(string: url), let scheme = u.scheme, let host = u.host, !password.isEmpty else { return nil }
        let origin = "\(scheme)://\(host)\(u.port.map { ":\($0)" } ?? "")"
        originURL = origin + "/"
        signonRealm = origin + "/"
        self.username = username
        self.password = password
        self.created = created
    }

    public init(originURL: String, actionURL: String, usernameElement: String, username: String, passwordElement: String,
                password: String, signonRealm: String, created: Int64) {
        self.originURL = originURL; self.actionURL = actionURL; self.usernameElement = usernameElement
        self.username = username; self.passwordElement = passwordElement; self.password = password
        self.signonRealm = signonRealm; self.created = created
    }
}

public struct ImportedCredentials {
    public var cookies: [ImportedCookie]
    public var logins: [ImportedLogin]
    public var isEmpty: Bool { cookies.isEmpty && logins.isEmpty }

    public init(cookies: [ImportedCookie] = [], logins: [ImportedLogin] = []) {
        self.cookies = cookies
        self.logins = logins
    }
}
