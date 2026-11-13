import Foundation

/// Cra's own unpacked extensions: Extensions/ in Cra's data folder, one folder per extension,
/// which Chromium loads with --load-extension at start-up (location 8, COMMAND_LINE).
/// Settings ▸ Extensions ▸ Add Unpacked Extension… copies a folder in; Remove deletes it; either
/// takes effect at the next launch. The Mac's ExtensionStore and the Windows Settings pane share it.
public enum ExtensionFolders {
    /// Chromium's Manifest::Location for --load-extension.
    public static let commandLineLocation = 8

    public enum AddError: Error, Equatable, LocalizedError {
        case noManifest
        case unreadableManifest
        case themeOrApp

        public var errorDescription: String? {
            switch self {
            case .noManifest: return "That folder has no manifest.json."
            case .unreadableManifest: return "That folder’s manifest.json can’t be read."
            case .themeOrApp: return "That folder holds a theme or an app, not an extension."
            }
        }
    }

    /// The folders that load, in name order: each holds a manifest.json. A dot-named folder is an
    /// import still being copied (".<id>.importing"), so it waits.
    public static func loadable(in directory: URL) -> [URL] {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        return names.compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            return fm.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) ? folder : nil
        }
    }

    /// --load-extension's value, nil when there's nothing to load. Chromium splits it at commas,
    /// so a folder whose path has one can't be passed and is left out.
    public static func commandLineValue(_ folders: [URL]) -> String? { commandLineValue(paths: folders.map(\.path)) }

    /// The same for paths as the platform writes them (Windows: `C:\…`).
    public static func commandLineValue(paths: [String]) -> String? {
        let usable = paths.filter { !$0.isEmpty && !$0.contains(",") }
        return usable.isEmpty ? nil : usable.joined(separator: ",")
    }

    /// Where a copy of `folder` goes in `directory`: under its own name, else "<name>-2",
    /// "<name>-3", … when that is taken.
    public static func destination(for folder: URL, in directory: URL,
                                   exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let name = folder.lastPathComponent
        var dest = directory.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while exists(dest) {
            dest = directory.appendingPathComponent("\(name)-\(n)", isDirectory: true)
            n += 1
        }
        return dest
    }

    /// Copies the extension in `folder` into `directory` (made when missing) and returns the copy.
    /// `checkKind`: refuse a manifest that doesn't parse, and themes and hosted apps, which
    /// Cra's lists leave out (the Mac's pane copies any folder with a manifest).
    @discardableResult
    public static func add(folder: URL, to directory: URL, checkKind: Bool = true) throws -> URL {
        let fm = FileManager.default
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else { throw AddError.noManifest }
        if checkKind {
            guard let data = try? Data(contentsOf: manifestURL),
                  let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AddError.unreadableManifest }
            if m["theme"] != nil || m["app"] != nil { throw AddError.themeOrApp }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = destination(for: folder, in: directory)
        try fm.copyItem(at: folder, to: dest)
        return dest
    }

    /// Whether `folder` (an installed extension's) is one of the folders in `directory`, which is
    /// how a --load-extension install is told from one the person loaded elsewhere. Compared
    /// without case on Windows paths, where C:\Users and c:\users are the same folder.
    public static func contains(_ folder: URL, directory: URL) -> Bool {
        let parent = folder.standardizedFileURL.deletingLastPathComponent().path
        let dir = directory.standardizedFileURL.path
        let trim = { (p: String) in p.hasSuffix("/") || p.hasSuffix("\\") ? String(p.dropLast()) : p }
        return trim(parent).lowercased() == trim(dir).lowercased()
    }
}
