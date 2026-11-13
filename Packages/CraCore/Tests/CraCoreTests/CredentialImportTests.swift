import CraCore
import Foundation
import Testing

/// Passwords and sign-ins from a Chromium browser on Windows: os_crypt's key and values, the
/// rows read and written, and the staged file. The AES-GCM and SHA-256 vectors come from Python's
/// `cryptography` and `hashlib`.
struct CredentialImportTests {
    static func hex(_ s: String) -> Data {
        var bytes: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            bytes.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return Data(bytes)
    }

    static let key = hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    static let nonce = hex("cafebabefacedbaddecaf888")

    @Test func aesGCMMatchesTheReference() {
        let empty = AESGCM.seal(Data(), key: Self.key, nonce: Self.nonce)
        #expect(empty?.ciphertext == Data() && empty?.tag == Self.hex("5b0a77e3716cc7e86cf71b26dee7d5a4"))
        let short = AESGCM.seal(Data("hunter2".utf8), key: Self.key, nonce: Self.nonce)
        #expect(short?.ciphertext == Self.hex("e2d6ce52cf087d") && short?.tag == Self.hex("f1741f91f021d4f3276d885331bc60fa"))
        let text = Data("The quick brown fox jumps over the lazy dog, twice over.".utf8)
        let long = AESGCM.seal(text, key: Self.key, nonce: Self.nonce, authenticating: Data("cra".utf8))
        #expect(long?.ciphertext == Self.hex("decbc506db0f26782d2b3faf146ae71f6b4fb871b56c07043dff6b07dbfb458bc535e12aa0ae304242344f4412f7570c3a31893ed5effafe"),
                "more than one block, the last one short")
        #expect(long?.tag == Self.hex("128067273012f0465018bd566b1ba7e8"), "with associated data")
        let aes128 = AESGCM.seal(Data("hunter2".utf8), key: Self.hex("feffe9928665731c6d6a8f9467308308"), nonce: Self.nonce)
        #expect(aes128.map { $0.ciphertext + $0.tag } == Self.hex("f3c74293bc81407028d98042c63f46dec7ee54dd559e1f"), "a 128-bit key")

        #expect(AESGCM.open(Self.hex("e2d6ce52cf087d"), key: Self.key, nonce: Self.nonce, tag: Self.hex("f1741f91f021d4f3276d885331bc60fa")) == Data("hunter2".utf8))
        #expect(AESGCM.open(Self.hex("e2d6ce52cf087e"), key: Self.key, nonce: Self.nonce, tag: Self.hex("f1741f91f021d4f3276d885331bc60fa")) == nil,
                "a changed byte fails the tag")
        #expect(AESGCM.open(Self.hex("e2d6ce52cf087d"), key: Data(repeating: 0, count: 32), nonce: Self.nonce, tag: Self.hex("f1741f91f021d4f3276d885331bc60fa")) == nil,
                "so does a wrong key")
        #expect(AESGCM.seal(Data(), key: Data(count: 20), nonce: Self.nonce) == nil && AESGCM.seal(Data(), key: Self.key, nonce: Data(count: 8)) == nil)
        let big = Data((0..<1_000).map { UInt8(truncatingIfNeeded: $0 * 7) })
        let sealed = AESGCM.seal(big, key: Self.key, nonce: Self.nonce)!
        #expect(AESGCM.open(sealed.ciphertext, key: Self.key, nonce: Self.nonce, tag: sealed.tag) == big)
    }

    @Test func sha256MatchesFIPS180() {
        func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(SHA256Hash.digest(Data())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(hex(SHA256Hash.digest(Data("abc".utf8))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(hex(SHA256Hash.digest(Data(".example.com".utf8))) == "1496295b2be8c88d729a34163e6885b0470833c34e8b5b53c370a9f5dbb77009")
        #expect(hex(SHA256Hash.digest(Data(repeating: 0x61, count: 1_000))) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    @Test func readsTheKeyAndTheValuesChromiumSealed() {
        let state = Data(#"{"os_crypt":{"encrypted_key":"RFBBUEkBAAAA0Iyd3wECAw=="},"profile":{}}"#.utf8)
        #expect(ChromiumOSCrypt.wrappedKey(localState: state) == Data([1, 0, 0, 0, 0xD0, 0x8C, 0x9D, 0xDF, 1, 2, 3]),
                "Local State's key without its DPAPI prefix")
        #expect(ChromiumOSCrypt.wrappedKey(localState: Data(#"{"os_crypt":{}}"#.utf8)) == nil)
        #expect(ChromiumOSCrypt.wrappedKey(localState: Data(#"{"os_crypt":{"encrypted_key":"AQID"}}"#.utf8)) == nil, "no DPAPI prefix")

        let v10 = Data("v10".utf8) + Self.nonce + Self.hex("e2d6ce52cf087d") + Self.hex("f1741f91f021d4f3276d885331bc60fa")
        #expect(ChromiumOSCrypt.classify(v10) == .aesGCM(nonce: Self.nonce, ciphertext: Self.hex("e2d6ce52cf087d"), tag: Self.hex("f1741f91f021d4f3276d885331bc60fa")))
        let never: (Data) -> Data? = { _ in nil }
        #expect(ChromiumOSCrypt.open(v10, key: Self.key, unprotect: never) == .plain(Data("hunter2".utf8)))
        #expect(ChromiumOSCrypt.open(Data("v11".utf8) + v10.dropFirst(3), key: Self.key, unprotect: never) == .plain(Data("hunter2".utf8)))
        #expect(ChromiumOSCrypt.open(v10, key: Data(count: 32), unprotect: never) == .failed)
        #expect(ChromiumOSCrypt.open(Data("v20".utf8) + v10.dropFirst(3), key: Self.key, unprotect: never) == .locked,
                "Chrome's app-bound values stay with Chrome")
        let legacy = Data([1, 0, 0, 0, 0xD0, 0x8C, 0x9D, 0xDF, 9, 9])
        #expect(ChromiumOSCrypt.open(legacy, key: Self.key, unprotect: { $0 == legacy ? Data("old".utf8) : nil }) == .plain(Data("old".utf8)),
                "a value from before Chrome 80 is a DPAPI blob of its own")
        #expect(ChromiumOSCrypt.open(Data(), key: Self.key, unprotect: never) == .plain(Data()))
        #expect(ChromiumOSCrypt.open(Data("v10short".utf8), key: Self.key, unprotect: never) == .failed)

        let sealed = ChromiumOSCrypt.seal(Data("secret".utf8), key: Self.key)!
        #expect(sealed.prefix(3) == Data("v10".utf8) && sealed.count == 3 + 12 + 6 + 16)
        #expect(ChromiumOSCrypt.open(sealed, key: Self.key, unprotect: never) == .plain(Data("secret".utf8)))
        #expect(ChromiumOSCrypt.seal(Data("secret".utf8), key: Self.key) != sealed, "each value gets its own nonce")
        #expect(ChromiumOSCrypt.seal(Data("hunter2".utf8), key: Self.key, nonce: Self.nonce) == v10)
    }

    @Test func cookieValuesCarryTheirHostsDigestFromVersion24() {
        let plain = ChromiumOSCrypt.cookiePlaintext("abc", host: ".example.com", version: 24)
        #expect(plain == Self.hex("1496295b2be8c88d729a34163e6885b0470833c34e8b5b53c370a9f5dbb77009") + Data("abc".utf8))
        #expect(ChromiumOSCrypt.cookieValue(plain, host: ".example.com", version: 24) == "abc")
        #expect(ChromiumOSCrypt.cookieValue(plain, host: ".other.com", version: 24) == nil, "another host's digest")
        #expect(ChromiumOSCrypt.cookiePlaintext("abc", host: ".example.com", version: 23) == Data("abc".utf8))
        #expect(ChromiumOSCrypt.cookieValue(Data("abc".utf8), host: ".example.com", version: 23) == "abc")
    }

    @Test func rowsComeOverAndGoIn() {
        let open: (Data) -> Data? = { $0 == Data([1]) ? Data("pw".utf8) : nil }
        let row: [String: Any] = ["origin_url": "https://a.com/login", "action_url": "https://a.com/go", "username_value": "me",
                                  "password_value": Data([1]), "signon_realm": "https://a.com/", "date_created": Int64(5)]
        let login = ChromiumCredentialRows.login(row, open: open)
        #expect(login?.username == "me" && login?.password == "pw" && login?.signonRealm == "https://a.com/" && login?.created == 5)
        var unreadable = row
        unreadable["password_value"] = Data([2])
        #expect(ChromiumCredentialRows.login(unreadable, open: open) == nil)

        let cookieRow: [String: Any] = ["host_key": ".a.com", "name": "sid", "value": "", "encrypted_value": Data([1]), "path": "/",
                                        "expires_utc": Int64(9), "is_secure": Int64(1), "samesite": Int64(1)]
        let cookie = ChromiumCredentialRows.cookie(cookieRow, now: 3) { sealed, host in sealed == Data([1]) && host == ".a.com" ? "token" : nil }
        #expect(cookie == ImportedCookie(host: ".a.com", name: "sid", value: "token", path: "/", expires: 9, created: 3, lastAccess: 3,
                                         secure: true, httpOnly: false, sameSite: 1))
        var plainCookie = cookieRow
        plainCookie["value"] = "clear"
        #expect(ChromiumCredentialRows.cookie(plainCookie, now: 3) { _, _ in nil }?.value == "clear", "an unsealed value reads as it is")
        #expect(ChromiumCredentialRows.cookiesQuery(now: 7, partitioned: true).hasSuffix("expires_utc > 7) AND top_frame_site_key = ''"))

        let columns = [
            ChromiumCredentialRows.Column(name: "origin_url", type: "VARCHAR", notNull: true, hasDefault: false),
            ChromiumCredentialRows.Column(name: "password_value", type: "BLOB", notNull: false, hasDefault: false),
            ChromiumCredentialRows.Column(name: "sender_email", type: "VARCHAR", notNull: true, hasDefault: false),
            ChromiumCredentialRows.Column(name: "sender_profile_image", type: "BLOB", notNull: true, hasDefault: false),
            ChromiumCredentialRows.Column(name: "id", type: "INTEGER", notNull: true, hasDefault: false),
            ChromiumCredentialRows.Column(name: "keychain_identifier", type: "BLOB", notNull: true, hasDefault: true),
        ]
        let fitted = ChromiumCredentialRows.fitted(ChromiumCredentialRows.loginColumns(login!, sealed: Data([7])), to: columns)
        #expect(fitted.map(\.name) == ["id", "origin_url", "password_value", "sender_email", "sender_profile_image"],
                "only the table's columns; NOT NULL ones without a default get a blank, the rest are left to SQLite")
        #expect(fitted.first { $0.name == "sender_profile_image" }?.value as? Data == Data())
        #expect(fitted.first { $0.name == "id" }?.value as? Int64 == 0)
        #expect(fitted.first { $0.name == "password_value" }?.value as? Data == Data([7]))
        #expect(ChromiumCredentialRows.Column(row: ["name": "x", "type": "INTEGER", "nn": Int64(1)])
                == ChromiumCredentialRows.Column(name: "x", type: "INTEGER", notNull: true, hasDefault: false))
        #expect(ChromiumCredentialRows.cookieColumns(cookie!, sealed: Data([8]))["has_cross_site_ancestor"] as? Bool == true)
    }

    @Test func stagedRowsKeepNoClearValuesAndGoToTheirProfiles() throws {
        let creds = ImportedCredentials(
            cookies: [ImportedCookie(host: ".a.com", name: "sid", value: "token", path: "/", expires: 0, created: 1, lastAccess: 1,
                                     secure: true, httpOnly: true, sameSite: -1, sourceProfile: "Profile 1")],
            logins: [ImportedLogin(url: "https://b.com/x", username: "me", password: "pw")!])
        var pending = PendingCredentials()
        let map = ImportProfileMap(folders: ["Profile 1": "Work"])
        let added = pending.add(creds, profiles: map) { Data("sealed:".utf8) + $0 }
        #expect(added)
        #expect(pending.cookies.first?.c.value == "" && pending.logins.first?.l.password == "", "the clear values don't stay")
        #expect(pending.cookies.first?.encrypted == Data("sealed:token".utf8))
        #expect(pending.folders == ["Default", "Work"] && pending.cookies(in: "Work").count == 1 && pending.logins(in: "Default").count == 1)

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pending)) as? [String: Any]
        let cookie = (json?["cookies"] as? [[String: Any]])?.first
        #expect(cookie?["c"] != nil && cookie?["encrypted"] != nil && cookie?["profile"] as? String == "Work", "the Mac's file format")
        #expect(try JSONDecoder().decode(PendingCredentials.self, from: JSONEncoder().encode(pending)) == pending)

        var failing = pending
        let addedNothing = !failing.add(creds) { _ in nil }
        #expect(addedNothing && failing == pending, "nothing is added when a value can't be sealed")
        pending.remove(folder: "Work", cookies: true, logins: true)
        #expect(pending.folders == ["Default"])
        pending.remove(folder: "Default", cookies: false, logins: true)
        #expect(pending.isEmpty)
    }

    @Test func theToastSaysWhatCameAndWhatStayed() {
        var report = CredentialImportReport()
        #expect(report.summary(from: "Edge") == nil)
        report.passwords = 12
        report.signIns = 40
        #expect(report.summary(from: "Edge") == "12 passwords and 40 sign-ins come in the next time Cra opens.")
        report.signIns = 0
        report.passwords = 1
        report.lockedSignIns = 300
        #expect(report.summary(from: "Chrome") == "1 password comes in the next time Cra opens. Chrome keeps its sign-ins locked to itself, so those stay there.")
        report.cookiesBusy = true
        #expect(report.summary(from: "Chrome")?.hasSuffix("Quit Chrome and import again to bring its sign-ins.") == true)
        report.failed = true
        #expect(report.summary(from: "Chrome") == "Cra couldn’t save the passwords and sign-ins from Chrome.")
    }

    @Test func windowsSourcesFindTheirUserData() {
        let folders = WindowsImportSource.Folders(local: URL(fileURLWithPath: "/L", isDirectory: true), roaming: URL(fileURLWithPath: "/R", isDirectory: true))
        let edge = WindowsImportSource.all.first { $0.id == "edge" }!
        #expect(edge.userData(in: folders)?.pathComponents.suffix(4) == ["L", "Microsoft", "Edge", "User Data"])
        let opera = WindowsImportSource.all.first { $0.id == "opera" }!
        #expect(opera.userData(in: folders)?.pathComponents.suffix(3) == ["R", "Opera Software", "Opera Stable"], "Opera's is under %APPDATA%")
        let helium = WindowsImportSource.all.first { $0.id == "helium" }!
        #expect(helium.userData(in: folders)?.pathComponents.suffix(4) == ["L", "imput", "Helium", "User Data"])
        let aside = WindowsImportSource.all.first { $0.id == "aside" }!
        #expect(aside.userData(in: folders)?.pathComponents.suffix(3) == ["L", "Aside", "User Data"])
        #expect(WindowsImportSource.names == "Arc, Chrome, Brave, Edge, Opera, Opera GX, Vivaldi, Chromium, Helium or Aside")
    }
}
