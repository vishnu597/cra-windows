import AppKit
import Foundation

/// A Chrome extension installed in Arc or Dia, read from the profile's
/// `Secure Preferences` (extensions.settings). Web Store installs keep their
/// manifest `key`, so a copy loaded unpacked keeps the same extension ID.
struct ImportableExtension: Identifiable {
    let id: String
    let name: String
    let version: String
    let folder: URL
    /// Turned on in at least one of `profiles`.
    var isEnabled: Bool
    let icon: NSImage?
    /// The source profile folders it is installed in, and whether it is on there (GitHub #131).
    var profiles: [String: Bool] = [:]

    /// Where Cra loads it: the profiles that have it on, else (picked though off) every one that has it.
    var sourceProfiles: Set<String> {
        let on = Set(profiles.filter(\.value).keys)
        return on.isEmpty ? Set(profiles.keys) : on
    }
}

enum ExtensionImporter {
    static func extensions(inBrowserSupportDir supportDir: URL) -> [ImportableExtension] {
        extensions(inUserData: supportDir.appendingPathComponent("User Data", isDirectory: true))
    }

    /// Every profile under a Chromium "User Data" folder (Chrome, Brave, Edge… keep it at the top level),
    /// one entry per extension with the profiles that have it.
    static func extensions(inUserData userData: URL) -> [ImportableExtension] {
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
        var out: [ImportableExtension] = []
        for profile in profiles {
            let dir = userData.appendingPathComponent(profile, isDirectory: true)
            for e in extensions(inProfile: dir) {
                if let i = out.firstIndex(where: { $0.id == e.id }) {
                    out[i].profiles[profile] = e.isEnabled
                    out[i].isEnabled = out[i].isEnabled || e.isEnabled
                } else {
                    var e = e
                    e.profiles = [profile: e.isEnabled]
                    out.append(e)
                }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The profile's pinned extensions (Chromium's extensions.pinned_extensions), in toolbar order.
    static func pinnedIDs(inProfile dir: URL) -> [String]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("Preferences")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["extensions"] as? [String: Any])?["pinned_extensions"] as? [String]
    }

    /// extensions.settings by extension ID, from the profile's files (InstalledExtensions).
    static func settings(inProfile dir: URL) -> [String: Any] { InstalledExtensions.settings(inProfile: dir) }

    /// Extensions turned off in this profile (chrome://extensions), of any install location:
    /// also the --load-extension ones (location 8), which Chromium loads disabled again.
    static func disabledIDs(inProfile dir: URL) -> Set<String> { disabledIDs(settings: settings(inProfile: dir)) }

    static func disabledIDs(settings: [String: Any]) -> Set<String> { InstalledExtensions.disabledIDs(settings: settings) }

    static func extensions(inProfile dir: URL) -> [ImportableExtension] { extensions(settings: settings(inProfile: dir), inProfile: dir) }

    /// The profile's extensions.settings, from its files or (Cra's own profiles) live from Chromium:
    /// its Web Store and unpacked installs (InstalledExtensions), with their icons.
    static func extensions(settings: [String: Any], inProfile dir: URL) -> [ImportableExtension] {
        InstalledExtensions.installed(settings: settings, inProfile: dir).map { e in
            ImportableExtension(id: e.id, name: e.manifest.name, version: e.manifest.version, folder: e.folder,
                                isEnabled: e.isEnabled, icon: icon(manifest: ["icons": e.manifest.icons], folder: e.folder))
        }
    }

    /// Descriptions are optional: Settings omits an unresolved message key instead of displaying it.
    static func localizedDescription(manifest: [String: Any], folder: URL) -> String {
        ExtensionManifest.localizedDescription(manifest: manifest, folder: folder)
    }

    /// Resolves `__MSG_key__` from the extension's default locale.
    static func localized(_ value: String, manifest: [String: Any], folder: URL) -> String {
        ExtensionManifest.localized(value, manifest: manifest, folder: folder)
    }

    /// The smallest manifest icon of at least `minPixels`, else the largest.
    static func icon(manifest: [String: Any], folder: URL, minPixels: Int = 48) -> NSImage? {
        guard let icons = manifest["icons"] as? [String: String] else { return nil }
        let sized = icons.compactMap { k, v in Int(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
        guard let pick = sized.first(where: { $0.0 >= minPixels }) ?? sized.last else { return nil }
        return NSImage(contentsOf: folder.appendingPathComponent(pick.1))
    }

    /// The manifest icons Chromium draws at `points` on 1x and 2x screens, in one image of that
    /// size: AppKit draws whichever file suits the screen. One 16 px file drawn on a Retina screen
    /// was twice its size and blurred (GitHub #349).
    static func icon(manifest: [String: Any], folder: URL, points: Int) -> NSImage? {
        guard let icons = manifest["icons"] as? [String: String] else { return nil }
        var image: NSImage?
        for file in ExtensionIcons.files(icons, points: points) {
            guard let loaded = NSImage(contentsOf: folder.appendingPathComponent(file)) else { continue }
            for rep in loaded.representations {
                // The first file's shape sets the image's; a square icon is points × points.
                let aspect = rep.pixelsWide > 0 && rep.pixelsHigh > 0 ? Double(rep.pixelsHigh) / Double(rep.pixelsWide)
                    : loaded.size.width > 0 ? loaded.size.height / loaded.size.width : 1
                let size = image?.size ?? NSSize(width: Double(points), height: Double(points) * aspect)
                if image == nil { image = NSImage(size: size) }
                rep.size = size
                image?.addRepresentation(rep)
            }
        }
        return image
    }
}
