import Foundation

/// Arc's per-profile "Download location" (Settings ▸ Profiles, `DownloadLocationView`): a folder,
/// or ask where to save each file (`arc.promptForDownload`). GitHub #190.
public struct DownloadLocation: Codable, Equatable, Sendable {
    /// The folder downloads go to; nil is the user's Downloads folder.
    public var folder: String?
    /// Show a save panel for each download, starting in `folder`.
    public var askWhereToSave: Bool

    public init(folder: String? = nil, askWhereToSave: Bool = false) {
        self.folder = folder
        self.askWhereToSave = askWhereToSave
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folder = try c.decodeIfPresent(String.self, forKey: .folder).flatMap { Self.isAbsolute($0) ? $0 : nil }
        askWhereToSave = try c.decodeIfPresent(Bool.self, forKey: .askWhereToSave) ?? false
    }

    /// A folder the file may name: a Mac path ("/…"), or on Windows a drive ("C:\\…", "D:/…") or a
    /// network share ("\\\\server\\share"). Anything relative ("../etc", "C:foo") is dropped.
    public static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        let c = Array(path.unicodeScalars)
        if c.count >= 3, ("A"..."Z").contains(c[0]) || ("a"..."z").contains(c[0]), c[1] == ":", c[2] == "\\" || c[2] == "/" {
            return true
        }
        // \\server\share: a server name after the two slashes, not "\\" alone or "\\?\" tricks.
        if path.hasPrefix("\\\\"), c.count > 2, c[2] != "\\", c[2] != "/", c[2] != "?", c[2] != "." { return true }
        return false
    }

    /// The folder to keep for one picked in Settings ▸ Profiles: nil (the Downloads default) for
    /// the Downloads folder itself, however its case or trailing slash differ, else the pick.
    public static func picked(_ path: String, downloads: String?) -> String? {
        func plain(_ p: String) -> String {
            var s = p.replacingOccurrences(of: "\\", with: "/").lowercased()
            while s.count > 1, s.hasSuffix("/") { s.removeLast() }
            return s
        }
        if let downloads, plain(path) == plain(downloads) { return nil }
        return path
    }

    /// The folder's own name, as Settings ▸ Profiles shows it ("Downloads" with none chosen).
    public var folderName: String {
        guard let folder else { return "Downloads" }
        let trimmed = folder.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        return trimmed.last.map(String.init) ?? folder
    }

    /// What the Windows bridge looks up when a download starts (cra_cef_set_download_locations):
    /// one line per profile that chose something, "<Chromium folder>\t<folder>\t<1 to ask>", the
    /// Chromium folder "Default" or "Profile <id>". Profiles that are gone are left out.
    public static func bridgeLines(_ locations: [String: DownloadLocation], profiles: [BrowserProfile]) -> String {
        locations.keys.sorted().compactMap { key -> String? in
            guard let location = locations[key] else { return nil }
            let folderName: String
            if key == Self.key(profileID: nil) {
                folderName = "Default"
            } else if let p = profiles.first(where: { $0.id.uuidString == key }) {
                folderName = p.directoryName
            } else {
                return nil
            }
            let folder = (location.folder ?? "").filter { $0 != "\t" && $0 != "\n" && $0 != "\r" }
            return "\(folderName)\t\(folder)\t\(location.askWhereToSave ? 1 : 0)"
        }.joined(separator: "\n")
    }

    /// The key AppSettings.downloadLocations files a profile under (nil is Default).
    public static func key(profileID: UUID?) -> String { profileID?.uuidString ?? "Default" }

    /// The folder to use: the chosen one, or `downloads` when none is chosen or it's gone.
    public func folderURL(downloads: URL, exists: (String) -> Bool) -> URL {
        guard let folder, exists(folder) else { return downloads }
        return URL(fileURLWithPath: folder, isDirectory: true)
    }
}

/// The file a download is saved as: only a name inside `folder` (no path, no "." or "..",
/// not hidden), " (n)" before the extension while the name is taken.
public enum DownloadFileName {
    public static func sanitized(_ suggested: String) -> String {
        var name = suggested.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        return name.trimmingCharacters(in: .whitespaces).isEmpty ? "download" : name
    }

    public static func unique(_ suggested: String, in folder: URL, exists: (String) -> Bool) -> URL {
        let name = sanitized(suggested)
        var dest = folder.appendingPathComponent(name)
        let base = dest.deletingPathExtension().lastPathComponent, ext = dest.pathExtension
        var n = 1
        while exists(dest.path) {
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return dest
    }
}
