import Foundation

/// The Chrome extensions a Chromium profile holds, from its `extensions.settings` (in `Secure
/// Preferences` on newer Chromium, `Preferences` on older), and what each one's manifest says.
/// The Mac reads Arc's, Dia's and Chrome's profiles with it (ExtensionImporter) and its own
/// (ExtensionStore); Windows reads Cra's profiles for the Extensions menu.
public enum InstalledExtensions {
    /// Chrome's Manifest::Location: 1 internal (the Web Store), 4 unpacked ("Load unpacked").
    /// Component (5), external (6, 7: other software's registrations) and command-line (8)
    /// installs belong to the browser or are loaded by Cra itself.
    public static let storeOrUnpacked: Set<Int> = [1, 4]

    /// Chromium's DISABLE_UNSUPPORTED_MANIFEST_VERSION: Chrome 139 and later turn every
    /// Manifest V2 extension off with it. Cra runs them (GitHub #228), so it doesn't count.
    public static let unsupportedManifestVersion = 1 << 23

    /// extensions.settings by extension ID, from the profile's files. Newer Chromium keeps
    /// extension state in Secure Preferences; older in Preferences.
    public static func settings(inProfile dir: URL) -> [String: Any] {
        var settings: [String: Any] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)) else { continue }
            settings.merge(self.settings(json: data)) { _, new in new }
        }
        return settings
    }

    /// extensions.settings out of a preferences file, or out of the pref itself (Chromium's live
    /// value, which is the dictionary without the `extensions.settings` around it).
    public static func settings(json data: Data) -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        if let ext = root["extensions"] as? [String: Any] { return ext["settings"] as? [String: Any] ?? [:] }
        return root
    }

    /// Turned off in chrome://extensions, or waiting for the person to approve it (an external
    /// install), but not merely for being Manifest V2.
    public static func isDisabled(_ s: [String: Any]) -> Bool {
        if let reasons = s["disable_reasons"] as? [Any], !reasons.isEmpty {
            return reasons.contains { ($0 as? Int) != unsupportedManifestVersion }
        }
        return (s["state"] as? Int) == 0
    }

    /// Extensions turned off in this profile, of any install location.
    public static func disabledIDs(settings: [String: Any]) -> Set<String> {
        Set(settings.compactMap { id, value in (value as? [String: Any]).flatMap { isDisabled($0) ? id : nil } })
    }

    public struct Installed: Equatable {
        public let id: String
        public let folder: URL
        public let isEnabled: Bool
        public let manifest: ExtensionManifest

        public init(id: String, folder: URL, isEnabled: Bool, manifest: ExtensionManifest) {
            self.id = id
            self.folder = folder
            self.isEnabled = isEnabled
            self.manifest = manifest
        }
    }

    /// The extensions in `settings` installed from `locations`, whose folder (an absolute path,
    /// or one under the profile's Extensions folder) has a manifest. Themes and hosted apps
    /// aren't extensions people pick, so they're left out. In name order.
    public static func installed(settings: [String: Any], inProfile dir: URL,
                                 locations: Set<Int> = storeOrUnpacked) -> [Installed] {
        settings.compactMap { id, value -> Installed? in
            guard let s = value as? [String: Any], let location = s["location"] as? Int,
                  locations.contains(location), let path = s["path"] as? String, !path.isEmpty else { return nil }
            let folder = isAbsolute(path) ? URL(fileURLWithPath: path, isDirectory: true)
                : dir.appendingPathComponent("Extensions", isDirectory: true).appendingPathComponent(path, isDirectory: true)
            guard let manifest = ExtensionManifest(folder: folder, fallbackName: id), !manifest.isThemeOrApp else { return nil }
            return Installed(id: id, folder: folder, isEnabled: !isDisabled(s), manifest: manifest)
        }
        .sorted { ($0.manifest.name.lowercased(), $0.id) < ($1.manifest.name.lowercased(), $1.id) }
    }

    /// `/Users/…` on the Mac, `C:\Users\…` or `\\server\…` on Windows; Web Store installs are
    /// stored relative ("<id>/<version>").
    public static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") { return true }
        let chars = Array(path.prefix(3))
        return chars.count == 3 && chars[0].isLetter && chars[1] == ":" && (chars[2] == "\\" || chars[2] == "/")
    }
}

/// What Cra reads from an extension's manifest.json.
public struct ExtensionManifest: Equatable {
    /// The name, with `__MSG_…__` resolved from the default locale (the folder's name, else the
    /// ID, when it can't be).
    public let name: String
    public let version: String
    /// Empty when it has none, or its message can't be resolved.
    public let description: String
    /// action / browser_action / page_action default_popup, relative to the folder.
    public let popupPath: String?
    /// options_ui.page or options_page, relative to the folder.
    public let optionsPath: String?
    /// The manifest's icons: pixel size → file.
    public let icons: [String: String]
    /// The action's default_icon (a path is the 16 px one), when it has one.
    public let actionIcons: [String: String]?
    /// Chrome's manifest key, which fixes the extension's ID.
    public let key: String?
    public let isThemeOrApp: Bool

    public init(name: String, version: String = "", description: String = "", popupPath: String? = nil,
                optionsPath: String? = nil, icons: [String: String] = [:], actionIcons: [String: String]? = nil,
                key: String? = nil, isThemeOrApp: Bool = false) {
        self.name = name
        self.version = version
        self.description = description
        self.popupPath = popupPath
        self.optionsPath = optionsPath
        self.icons = icons
        self.actionIcons = actionIcons
        self.key = key
        self.isThemeOrApp = isThemeOrApp
    }

    /// The manifest.json in `folder`; nil when there isn't one that parses.
    public init?(folder: URL, fallbackName: String) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.init(manifest: m, folder: folder, fallbackName: fallbackName)
    }

    public init(manifest m: [String: Any], folder: URL, fallbackName: String) {
        let title = Self.localized(m["name"] as? String ?? "", manifest: m, folder: folder)
        let action = (m["action"] ?? m["browser_action"] ?? m["page_action"]) as? [String: Any]
        let popup = action?["default_popup"] as? String
        self.init(name: title.isEmpty || Self.isMessage(title) ? fallbackName : title,
                  version: m["version"] as? String ?? "",
                  description: Self.localizedDescription(manifest: m, folder: folder),
                  popupPath: popup.flatMap { $0.isEmpty ? nil : $0 },
                  optionsPath: (m["options_ui"] as? [String: Any])?["page"] as? String ?? m["options_page"] as? String,
                  icons: m["icons"] as? [String: String] ?? [:],
                  // A path or {size: path} (React DevTools' grey "disabled" icon until a page uses React).
                  actionIcons: action?["default_icon"] as? [String: String] ?? (action?["default_icon"] as? String).map { ["16": $0] },
                  key: m["key"] as? String,
                  isThemeOrApp: m["theme"] != nil || m["app"] != nil)
    }

    /// The files to draw the extension's button at `points`, one per screen scale: the action's
    /// icons, else the extension's (ExtensionIcons).
    public func iconFiles(points: Int, scales: [Int] = [1, 2]) -> [String] {
        let action = actionIcons.map { ExtensionIcons.files($0, points: points, scales: scales) } ?? []
        return action.isEmpty ? ExtensionIcons.files(icons, points: points, scales: scales) : action
    }

    /// The description, empty when it has none or its message can't be resolved: Settings
    /// leaves an optional description out rather than show a message key.
    public static func localizedDescription(manifest: [String: Any], folder: URL) -> String {
        let value = localized(manifest["description"] as? String ?? "", manifest: manifest, folder: folder)
        return isMessage(value) ? "" : value
    }

    static func isMessage(_ value: String) -> Bool { value.hasPrefix("__MSG_") && value.hasSuffix("__") }

    /// Resolves `__MSG_key__` from the extension's default locale, then English.
    public static func localized(_ value: String, manifest: [String: Any], folder: URL) -> String {
        guard isMessage(value) else { return value }
        let key = String(value.dropFirst(6).dropLast(2)).lowercased()
        let locales = [manifest["default_locale"] as? String, "en", "en_US"].compactMap { $0 }
        for locale in locales {
            let url = folder.appendingPathComponent("_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: url),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (k, v) in messages where k.lowercased() == key {
                if let m = (v as? [String: Any])?["message"] as? String { return m }
            }
        }
        return value
    }
}
