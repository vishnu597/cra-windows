import Foundation

/// Imported passwords and cookies waiting for Cra's Chromium profile: Chromium keeps Login Data
/// and Cookies locked while it runs, so the rows are staged in a file, already sealed with the
/// profile's key (no easier to read than the databases they feed), and written in on the next
/// launch before Chromium opens them. Rows from an Arc profile go to the Cra profile its spaces
/// were put on (GitHub #131). The same file as the Mac's `CredentialImport` writes.
public struct PendingCredentials: Codable, Equatable {
    /// `profile`: the Cra profile folder it goes to; nil (files from before #131) is Default.
    public struct Cookie: Codable, Equatable {
        public var c: ImportedCookie
        public var encrypted: Data
        public var profile: String?
    }

    public struct Login: Codable, Equatable {
        public var l: ImportedLogin
        public var encrypted: Data
        public var profile: String?
    }

    public var cookies: [Cookie] = []
    public var logins: [Login] = []

    public init() {}

    public var isEmpty: Bool { cookies.isEmpty && logins.isEmpty }

    /// Adds `credentials`, each row sealed by `seal` for the Cra profile `profiles` maps its source
    /// profile to; the clear values don't stay in the rows. False (and nothing added) when a
    /// value couldn't be sealed.
    public mutating func add(_ credentials: ImportedCredentials, profiles: ImportProfileMap = ImportProfileMap(),
                             seal: (Data) -> Data?) -> Bool {
        var cookies: [Cookie] = [], logins: [Login] = []
        for var c in credentials.cookies {
            guard let sealed = seal(Data(c.value.utf8)) else { return false }
            c.value = ""
            cookies.append(Cookie(c: c, encrypted: sealed, profile: profiles.craFolder(forSource: c.sourceProfile)))
        }
        for var l in credentials.logins {
            guard let sealed = seal(Data(l.password.utf8)) else { return false }
            l.password = ""
            logins.append(Login(l: l, encrypted: sealed, profile: profiles.craFolder(forSource: l.sourceProfile)))
        }
        self.cookies += cookies
        self.logins += logins
        return true
    }

    /// The Cra profile folders rows wait for, Default first.
    public var folders: [String] {
        let all = Set(cookies.map { $0.profile ?? "Default" } + logins.map { $0.profile ?? "Default" })
        return all.sorted { ($0 == "Default" ? 0 : 1, $0) < ($1 == "Default" ? 0 : 1, $1) }
    }

    public func cookies(in folder: String) -> [Cookie] { cookies.filter { ($0.profile ?? "Default") == folder } }
    public func logins(in folder: String) -> [Login] { logins.filter { ($0.profile ?? "Default") == folder } }

    /// Drops what was written into `folder`.
    public mutating func remove(folder: String, cookies dropCookies: Bool, logins dropLogins: Bool) {
        if dropCookies { cookies.removeAll { ($0.profile ?? "Default") == folder } }
        if dropLogins { logins.removeAll { ($0.profile ?? "Default") == folder } }
    }
}

/// What an import of passwords and sign-ins did, for the toast after the spaces' summary.
public struct CredentialImportReport: Equatable {
    public var passwords = 0
    public var signIns = 0
    /// Sign-ins sealed to their own browser (Chrome's app-bound "v20").
    public var lockedSignIns = 0
    public var lockedPasswords = 0
    /// The browser held its Cookies file (it was running), so no sign-ins were read.
    public var cookiesBusy = false
    /// Cra couldn't stage what it read.
    public var failed = false

    public init() {}

    /// One or two sentences, or nil when there was nothing to say.
    public func summary(from browser: String) -> String? {
        if failed { return "Cra couldn’t save the passwords and sign-ins from \(browser)." }
        var parts: [String] = []
        let words = [count(passwords, "password"), count(signIns, "sign-in")].compactMap { $0 }
        if !words.isEmpty {
            let one = passwords + signIns == 1
            parts.append("\(words.joined(separator: " and ")) \(one ? "comes" : "come") in the next time Cra opens.")
        }
        if cookiesBusy {
            parts.append("Quit \(browser) and import again to bring its sign-ins.")
        } else if lockedSignIns > 0 || lockedPasswords > 0 {
            let what = lockedPasswords > 0 && lockedSignIns > 0 ? "passwords and sign-ins" : (lockedPasswords > 0 ? "passwords" : "sign-ins")
            parts.append("\(browser) keeps its \(what) locked to itself, so those stay there.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func count(_ n: Int, _ noun: String) -> String? {
        n == 0 ? nil : "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
