import Foundation

/// How Chromium on Windows seals saved passwords and cookies (components/os_crypt): one AES-256
/// key per User Data folder, kept in Local State as `os_crypt.encrypted_key` (base64 of "DPAPI"
/// and the key wrapped by Windows' DPAPI for the signed-in user), and each value as "v10", a
/// 12-byte nonce, the AES-GCM ciphertext and its 16-byte tag. Values from before Chrome 80 are a
/// DPAPI blob of their own. Chrome 127 and later seal cookies with "v20", a key only Chrome's
/// elevation service can unwrap (app-bound encryption): those stay where they are. Unwrapping
/// with DPAPI is the app's job (`unprotect`); the rest is here so it is tested off Windows.
public enum ChromiumOSCrypt {
    /// What a sealed value is.
    public enum Sealed: Equatable {
        case empty
        /// "v10" or "v11": AES-GCM with the Local State key.
        case aesGCM(nonce: Data, ciphertext: Data, tag: Data)
        /// "v20": app-bound to the browser that wrote it.
        case appBound
        /// A DPAPI blob from before Chrome 80.
        case dpapi(Data)
        case unknown
    }

    /// What reading a value gave.
    public enum Opened: Equatable {
        case plain(Data)
        /// App-bound ("v20"): only its own browser can read it.
        case locked
        /// A wrong key, a changed value or a format this doesn't know.
        case failed
    }

    static let keyPrefix = Data("DPAPI".utf8)
    /// DPAPI blobs start with their version (1) and the DPAPI provider's GUID.
    static let dpapiHeader: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0xD0, 0x8C, 0x9D, 0xDF]
    static let sealPrefix = Data("v10".utf8)

    /// The DPAPI-wrapped key from a Local State file's contents; nil without one.
    public static func wrappedKey(localState: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: localState) as? [String: Any],
              let osCrypt = json["os_crypt"] as? [String: Any], let encoded = osCrypt["encrypted_key"] as? String,
              let raw = Data(base64Encoded: encoded) else { return nil }
        let bytes = [UInt8](raw)
        guard bytes.count > keyPrefix.count, Data(bytes.prefix(keyPrefix.count)) == keyPrefix else { return nil }
        return Data(bytes.dropFirst(keyPrefix.count))
    }

    public static func classify(_ value: Data) -> Sealed {
        let bytes = [UInt8](value)
        guard !bytes.isEmpty else { return .empty }
        let version = Data(bytes.prefix(3))
        if version == Data("v10".utf8) || version == Data("v11".utf8) {
            guard bytes.count >= 3 + AESGCM.nonceSize + AESGCM.tagSize else { return .unknown }
            let body = 3 + AESGCM.nonceSize, tag = bytes.count - AESGCM.tagSize
            return .aesGCM(nonce: Data(bytes[3..<body]), ciphertext: Data(bytes[body..<tag]), tag: Data(bytes[tag...]))
        }
        if version == Data("v20".utf8) { return .appBound }
        if bytes.starts(with: dpapiHeader) { return .dpapi(value) }
        return .unknown
    }

    /// A value read with the profile's `key`; `unprotect` unwraps a DPAPI blob (pre-Chrome 80).
    public static func open(_ value: Data, key: Data, unprotect: (Data) -> Data?) -> Opened {
        switch classify(value) {
        case .empty: return .plain(Data())
        case .aesGCM(let nonce, let ciphertext, let tag):
            return AESGCM.open(ciphertext, key: key, nonce: nonce, tag: tag).map(Opened.plain) ?? .failed
        case .appBound: return .locked
        case .dpapi(let blob): return unprotect(blob).map(Opened.plain) ?? .failed
        case .unknown: return .failed
        }
    }

    /// `plain` sealed as Chromium writes it with `key` ("v10"); a fresh random nonce unless given.
    public static func seal(_ plain: Data, key: Data, nonce: Data? = nil) -> Data? {
        let nonce = nonce ?? randomNonce()
        guard let sealed = AESGCM.seal(plain, key: key, nonce: nonce) else { return nil }
        return sealPrefix + nonce + sealed.ciphertext + sealed.tag
    }

    static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<AESGCM.nonceSize).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    // MARK: Cookies

    /// The Cookies database version from which each value starts with SHA-256 of its host.
    public static let hostDigestVersion = 24

    /// A cookie's value from what its sealed bytes opened to: the host digest checked and taken
    /// off from version 24 on. nil when the digest is another host's.
    public static func cookieValue(_ plain: Data, host: String, version: Int) -> String? {
        var bytes = [UInt8](plain)
        if version >= hostDigestVersion {
            guard bytes.count >= 32, Array(bytes.prefix(32)) == SHA256Hash.digest(Data(host.utf8)) else { return nil }
            bytes.removeFirst(32)
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// What to seal for a cookie's value in a Cookies database of `version`.
    public static func cookiePlaintext(_ value: String, host: String, version: Int) -> Data {
        version >= hostDigestVersion ? Data(SHA256Hash.digest(Data(host.utf8))) + Data(value.utf8) : Data(value.utf8)
    }
}
