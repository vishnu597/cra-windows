import Foundation

/// Bringing another browser's Chrome extensions into Cra's Extensions/ folder (the Mac's import
/// step and Windows' Import from Another Browser): each one the browser's profiles have, copied in
/// as Extensions/<id>. A Web Store install keeps its manifest `key`, so the copy Cra loads with
/// --load-extension has the same extension ID, and with it the same storage and settings page.
public enum ExtensionImport {
    /// An extension a browser's profiles have, once however many profiles have it.
    public struct Candidate: Equatable, Identifiable {
        public let id: String
        public let folder: URL
        public let manifest: ExtensionManifest
        /// On in at least one of `profiles`.
        public var isEnabled: Bool
        /// The source profile folders it is installed in, and whether it is on there (GitHub #131).
        public var profiles: [String: Bool]

        public var name: String { manifest.name }
        public var version: String { manifest.version }

        public init(id: String, folder: URL, manifest: ExtensionManifest, isEnabled: Bool, profiles: [String: Bool] = [:]) {
            self.id = id
            self.folder = folder
            self.manifest = manifest
            self.isEnabled = isEnabled
            self.profiles = profiles
        }

        /// Where Cra loads it: the profiles that have it on, else (picked though off) every one that has it.
        public var sourceProfiles: Set<String> {
            let on = Set(profiles.filter(\.value).keys)
            return on.isEmpty ? Set(profiles.keys) : on
        }
    }

    /// Every Web Store and unpacked extension in the profiles under a Chromium "User Data" folder
    /// (Default, "Profile <n>" and Yab's "space-<id>"), one entry per extension ID with the profiles that have it.
    /// The folder of the first profile that has it is the one copied. In name order.
    public static func candidates(inUserData userData: URL) -> [Candidate] {
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter(ChromiumImporter.isProfileFolder).sorted()
        var out: [Candidate] = []
        for profile in profiles {
            let dir = userData.appendingPathComponent(profile, isDirectory: true)
            for e in InstalledExtensions.installed(settings: InstalledExtensions.settings(inProfile: dir), inProfile: dir) {
                if let i = out.firstIndex(where: { $0.id == e.id }) {
                    out[i].profiles[profile] = e.isEnabled
                    out[i].isEnabled = out[i].isEnabled || e.isEnabled
                } else {
                    out.append(Candidate(id: e.id, folder: e.folder, manifest: e.manifest, isEnabled: e.isEnabled, profiles: [profile: e.isEnabled]))
                }
            }
        }
        return out.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    /// What the extensions step offers from a browser: the ones Cra doesn't have yet, in order,
    /// those ticked to start with, and how many Cra has already. An empty `fresh` skips the step.
    public struct Offer: Equatable {
        public let fresh: [Candidate]
        public let ticked: Set<String>
        public let alreadyIn: Int
    }

    public static func offer(_ candidates: [Candidate], installed: Set<String>) -> Offer {
        let fresh = candidates.filter { !installed.contains($0.id) }
        return Offer(fresh: fresh, ticked: preselected(fresh, installed: installed), alreadyIn: candidates.count - fresh.count)
    }

    /// The step's words: `alreadyIn` says how many of the browser's are in Cra already.
    public static func offerWords(alreadyIn: Int) -> String {
        var words = "Cra copies the ones you pick into its own Extensions folder. They load in every profile when Cra next starts."
        if alreadyIn > 0 { words += alreadyIn == 1 ? " One is in Cra already." : " \(alreadyIn) are in Cra already." }
        return words
    }

    /// The ones ticked to start with: turned on in the browser, and not in Cra already.
    public static func preselected(_ candidates: [Candidate], installed: Set<String>) -> Set<String> {
        Set(candidates.filter { $0.isEnabled && !installed.contains($0.id) }.map(\.id))
    }

    /// Copies `folder` into `directory` (made when missing) as `<id>`, replacing an older copy of
    /// the same extension, and returns the copy. It is copied to ".<id>.importing" first, which
    /// `ExtensionFolders.loadable` skips, so a launch never loads half a copy. The Web Store's
    /// verification hashes (_metadata) don't apply to an unpacked copy and are left out.
    @discardableResult
    public static func copy(_ folder: URL, id: String, into directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent(id, isDirectory: true)
        let staging = directory.appendingPathComponent(".\(id).importing", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: folder, to: staging)
        try? fm.removeItem(at: staging.appendingPathComponent("_metadata"))
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: staging, to: dest)
        return dest
    }

    /// What an import of extensions did, for the import's result: nil when none were picked.
    public static func summary(imported: Int, failed: [String]) -> String? {
        var parts: [String] = []
        if imported > 0 {
            parts.append(imported == 1 ? "1 extension comes in when Cra restarts." : "\(imported) extensions come in when Cra restarts.")
        }
        if !failed.isEmpty { parts.append("Cra couldn’t copy \(failed.joined(separator: ", ")).") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
