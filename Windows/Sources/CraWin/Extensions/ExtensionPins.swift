import CraCore
import Foundation

/// The extensions pinned to the toolbar (the Mac's ExtensionStore pins): pinned-extensions.json in
/// Cra's data folder, the Mac's file, a list for each Chromium profile ("Default", "Profile <id>").
/// The Site Control Center's badge pins and unpins; the toolbar shows a button for each pin.
@MainActor
final class ExtensionPins {
    static let shared = ExtensionPins()

    /// Called after a pin or an unpin, for the toolbars and Site Control Centers to follow.
    var onChange: [() -> Void] = []
    private(set) var pins: PinnedExtensions
    private let file: URL

    init(file: URL = WinPaths.supportDir.appendingPathComponent("pinned-extensions.json")) {
        self.file = file
        pins = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(PinnedExtensions.self, from: $0) } ?? PinnedExtensions()
    }

    /// The Chromium profile folder's name for a page's profile path (nil: Default).
    static func profile(_ path: String?) -> String {
        path.map { URL(fileURLWithPath: $0, isDirectory: true).lastPathComponent } ?? "Default"
    }

    func isPinned(_ id: String, profilePath: String?) -> Bool {
        pins.isPinned(id, inProfile: Self.profile(profilePath))
    }

    /// The toolbar's pins in the profile: the ones that are installed and turned on.
    func toolbarIDs(profilePath: String?, enabled: [ExtensionList.Entry]) -> [String] {
        pins.toolbarIDs(inProfile: Self.profile(profilePath), enabled: Set(enabled.map(\.id)))
    }

    func togglePin(_ id: String, profilePath: String?) {
        let profile = Self.profile(profilePath)
        let before = pins
        pins.setPinned(id, !pins.isPinned(id, inProfile: profile), inProfile: profile)
        guard pins != before else { return }
        save()
        for f in onChange { f() }
    }

    private func save() {
        do {
            try JSONEncoder().encode(pins).write(to: file, options: .atomic)
        } catch {
            print("Cra: pinned-extensions.json could not be saved: \(error)")
        }
    }
}
