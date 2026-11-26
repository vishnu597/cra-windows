import Foundation

/// The app icons Settings ▸ General offers (Arc's Icon tab, GitHub #372): Cra's own set, each a
/// 512 px picture in resources/app-icons named by its id, and on the Mac an image of the user's
/// own. Which one is picked lives in the app's preferences under `storageKey` (the Mac's
/// defaults, Windows' HKCU\Software\Cra), not in the data folder.
public enum AppIconChoice {
    public struct Option: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Segments: the icon the app is built with (AppIcon.icns, Cra.ico).
    public static let defaultID = "segments"
    public static let customID = "custom"
    public static let storageKey = "appIcon"

    /// Segments, then Arc's own icon set in Arc's order (its AppIcon cases: original, candy, hologram, neon,
    /// flutedGlass, schoolbook, colorful, and the canary and Early Birds channel icons), redrawn around Cra's C
    /// by Provok (github.com/mat-up/cra-icons, MIT; sources in brand/arc-icons), then Cra's earlier alternates.
    public static let presets = [
        Option(id: defaultID, name: "Segments"),
        Option(id: "original", name: "Original"),
        Option(id: "candy", name: "Candy"),
        Option(id: "hologram", name: "Hologram"),
        Option(id: "neon", name: "Neon"),
        Option(id: "fluted-glass", name: "Fluted Glass"),
        Option(id: "schoolbook", name: "Schoolbook"),
        Option(id: "colorful", name: "Colorful"),
        Option(id: "canary", name: "Canary"),
        Option(id: "early-birds", name: "Early Birds"),
        Option(id: "midnight", name: "Midnight"),
        Option(id: "mono", name: "Mono"),
        Option(id: "violet", name: "Violet"),
    ]

    /// The icon to show for what was stored: a preset's id, the user's own while there is one,
    /// else Segments (nothing stored, a name a later version dropped, a custom icon since removed).
    public static func resolved(stored: String?, hasCustom: Bool) -> String {
        guard let stored else { return defaultID }
        if presets.contains(where: { $0.id == stored }) { return stored }
        return stored == customID && hasCustom ? customID : defaultID
    }

    /// The bundled picture of a preset, relative to the app's resources; nil for the user's own.
    public static func bundledFile(_ id: String) -> String? {
        presets.contains { $0.id == id } ? "app-icons/\(id).png" : nil
    }
}
