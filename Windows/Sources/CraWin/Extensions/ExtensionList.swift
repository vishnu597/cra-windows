import CraCEFWin
import CraCore
import Foundation
import WinUI

/// The Chrome extensions installed in Cra's Chromium profiles (the Mac's ExtensionStore, for the
/// Web Store and "Load unpacked" installs Chromium keeps itself): each profile's live
/// extensions.settings, read again when Chromium says it changed. CraCore's InstalledExtensions
/// reads them; the Site Control Center shows a page's profile's.
@MainActor
final class ExtensionList {
    static let shared = ExtensionList()

    struct Entry: Equatable {
        let id: String
        let name: String
        let isEnabled: Bool
        let folder: URL
        let manifest: ExtensionManifest

        var launch: ExtensionLaunch.Extension {
            ExtensionLaunch.Extension(id: id, popupPath: manifest.popupPath, optionsPath: manifest.optionsPath, enabled: isEnabled)
        }
    }

    /// Called after a profile's extensions changed (an install, a switch, a removal).
    var onChange: [() -> Void] = []
    /// Icons by "<folder>|<file>", decoded once.
    private var icons: [String: WriteableBitmap] = [:]

    private init() {
        cra_cef_set_extensions_changed_handler(nil) { _ in
            onMain { ExtensionList.shared.changed() }
        }
    }

    private func changed() {
        icons.removeAll()
        for f in onChange { f() }
    }

    /// The extensions of the profile whose folder is `profilePath` (nil: Default), turned off
    /// ones included, by name. Live from Chromium once the profile has loaded, else from its files.
    func entries(profilePath: String?, chromiumCache: URL) -> [Entry] {
        let dir = profilePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? chromiumCache.appendingPathComponent("Default", isDirectory: true)
        let settings = Self.liveSettings(profilePath: profilePath) ?? InstalledExtensions.settings(inProfile: dir)
        return InstalledExtensions.installed(settings: settings, inProfile: dir).map {
            Entry(id: $0.id, name: $0.manifest.name, isEnabled: $0.isEnabled, folder: $0.folder, manifest: $0.manifest)
        }
    }

    /// The ones that run: Arc's Site Control Center and Chrome's toolbar leave turned-off
    /// extensions out, and running one crashes Chromium (the Mac's #41).
    func enabled(profilePath: String?, chromiumCache: URL) -> [Entry] {
        entries(profilePath: profilePath, chromiumCache: chromiumCache).filter(\.isEnabled)
    }

    private static func liveSettings(profilePath: String?) -> [String: Any]? {
        guard let json = cra_cef_preference_json(profilePath, "extensions.settings") else { return nil }
        defer { cra_data_free(json) }
        return InstalledExtensions.settings(json: Data(String(cString: json).utf8))
    }

    /// The extension's button icon at `points` DIPs for a screen at `scale`: the action's icon
    /// file Chromium would draw (ExtensionIcons), decoded once.
    func icon(_ entry: Entry, points: Int, scale: Double) -> WriteableBitmap? {
        let files = entry.manifest.iconFiles(points: points, scales: [1, 2])
        guard let file = scale > 1.25 ? files.last : files.first else { return nil }
        let key = entry.folder.path + "|" + file
        if let icon = icons[key] { return icon }
        guard let data = try? Data(contentsOf: entry.folder.appendingPathComponent(file)),
              let bitmap = Pixels.decode(data)?.bitmap() else { return nil }
        icons[key] = bitmap
        return bitmap
    }
}
