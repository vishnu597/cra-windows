import Foundation

/// Remove in chrome://extensions for an extension Cra loads from a folder in Extensions/ (an import
/// from Arc, Dia or Chrome, or Add Unpacked Extension…). Chromium loads those with --load-extension
/// (location 8, COMMAND_LINE), and its uninstall only deletes the extension's entry in the
/// profile's extensions.settings; the next launch loaded the folder again, so such an extension
/// could be turned off (Chromium keeps that switch) but not removed. A copy a profile loaded this
/// session whose entry has left that profile's live settings was removed there: it stops loading
/// in that profile. Chromium deletes the entry only on an uninstall: a reload, a switch or an
/// install over it (the Web Store's, #203) keeps it.
public struct ExtensionCopyRemovals: Sendable {
    /// Location 8 in Chromium's extensions.settings: --load-extension.
    public static let commandLineLocation = 8

    /// The ID Chromium gave each copy it loaded this session, by "<profile>/<folder>".
    private var loaded: [String: String] = [:]

    public init() {}

    /// Reads one profile's live extensions.settings for the copy Extensions/<folder> at `copyPath`,
    /// whose ID by Cra's reckoning is `extensionID`. True once, when the profile had loaded the
    /// copy this session and has no entry for it any more.
    public mutating func wasRemoved(folder: String, copyPath: String, extensionID: String, profile: String,
                                    settings: [String: Any]) -> Bool {
        let key = "\(profile)/\(folder)"
        if let id = Self.loadedID(copyPath: copyPath, extensionID: extensionID, settings: settings) {
            loaded[key] = id
            return false
        }
        guard let id = loaded[key], settings[id] == nil else { return false }
        loaded[key] = nil
        return true
    }

    /// The ID of the profile's --load-extension install of the copy: its own ID, or the entry
    /// whose path is the copy's (Chromium names a keyless copy after its real path).
    static func loadedID(copyPath: String, extensionID: String, settings: [String: Any]) -> String? {
        func isCommandLine(_ value: Any?) -> Bool { ((value as? [String: Any])?["location"] as? Int) == commandLineLocation }
        if isCommandLine(settings[extensionID]) { return extensionID }
        let copy = normalized(copyPath)
        return settings.first { _, value in
            guard isCommandLine(value), let path = (value as? [String: Any])?["path"] as? String,
                  path.hasPrefix("/") || isWindowsPath(path) else { return false }
            return normalized(path) == copy
        }?.key
    }

    /// `C:\Users\…` (or with forward slashes): a Windows Chromium's path.
    static func isWindowsPath(_ path: String) -> Bool {
        let c = Array(path.utf8.prefix(3))
        return c.count == 3 && ((c[0] >= 65 && c[0] <= 90) || (c[0] >= 97 && c[0] <= 122)) && c[1] == UInt8(ascii: ":")
            && (c[2] == UInt8(ascii: "\\") || c[2] == UInt8(ascii: "/"))
    }

    /// The ID Chromium gives an extension whose manifest has a `key` (base64): the first 128 bits of
    /// its SHA-256, each hex digit as a-p. nil without a key (a keyless copy is found by its path).
    public static func keyedID(base64Key: String?) -> String? {
        guard let key = base64Key, let data = Data(base64Encoded: key) else { return nil }
        let a = UInt8(ascii: "a")
        return String(decoding: SHA256Hash.digest(data).prefix(16).flatMap { [a + ($0 >> 4), a + ($0 & 0xF)] }, as: UTF8.self)
    }

    private static func normalized(_ path: String) -> String {
        // Windows' paths compare without case, with either slash.
        if isWindowsPath(path) {
            var p = path.replacingOccurrences(of: "/", with: "\\").lowercased()
            while p.count > 3 && p.hasSuffix("\\") { p.removeLast() }
            return p
        }
        var p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
