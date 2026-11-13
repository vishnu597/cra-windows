import CraCore
import Foundation
import Testing

/// Another browser's extensions, as the import offers them and copies them into Cra's folder.
struct ExtensionImportTests {
    private static func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-ext-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A profile under `userData` with these extensions.settings in Secure Preferences.
    private static func profile(_ name: String, in userData: URL, settings: [String: Any]) throws -> URL {
        let dir = userData.appendingPathComponent(name, isDirectory: true)
        let prefs = try JSONSerialization.data(withJSONObject: ["extensions": ["settings": settings]])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try prefs.write(to: dir.appendingPathComponent("Secure Preferences"))
        return dir
    }

    @Test func eachExtensionIsOfferedOnceWithTheProfilesThatHaveIt() throws {
        let userData = try Self.temp()
        defer { try? FileManager.default.removeItem(at: userData) }
        let def = try Self.profile("Default", in: userData, settings: [
            "blocker": ["location": 1, "path": "blocker/1.2_0"],
            "notes": ["location": 1, "path": "notes/3_0", "disable_reasons": [1]],
        ])
        let second = try Self.profile("Profile 2", in: userData, settings: [
            "blocker": ["location": 1, "path": "blocker/1.2_0", "disable_reasons": [1]],
            "notes": ["location": 1, "path": "notes/3_0"],
            "theme": ["location": 1, "path": "theme/1_0"],
        ])
        _ = try Self.profile("System Profile", in: userData, settings: ["blocker": ["location": 1, "path": "blocker/1.2_0"]])
        for dir in [def, second] {
            try Self.write(#"{"name":"Blocker","version":"1.2","key":"abc"}"#, to: dir.appendingPathComponent("Extensions/blocker/1.2_0/manifest.json"))
            try Self.write(#"{"name":"another Notes","version":"3"}"#, to: dir.appendingPathComponent("Extensions/notes/3_0/manifest.json"))
        }
        try Self.write(#"{"name":"Dark","version":"1","theme":{}}"#, to: second.appendingPathComponent("Extensions/theme/1_0/manifest.json"))

        let offered = ExtensionImport.candidates(inUserData: userData)
        #expect(offered.map(\.name) == ["another Notes", "Blocker"], "by name, case aside; no theme, no System Profile")
        let blocker = try #require(offered.first { $0.id == "blocker" })
        #expect(blocker.profiles == ["Default": true, "Profile 2": false] && blocker.isEnabled)
        #expect(blocker.sourceProfiles == ["Default"], "it loads where it was on")
        #expect(blocker.version == "1.2")
        #expect(blocker.folder.standardizedFileURL == def.appendingPathComponent("Extensions/blocker/1.2_0").standardizedFileURL,
                "the first profile's copy")
        #expect(ExtensionImport.candidates(inUserData: userData.appendingPathComponent("none")).isEmpty)
    }

    @Test func turnedOnOnesNotInCraAreTicked() {
        let manifest = ExtensionManifest(name: "E", version: "1")
        let folder = FileManager.default.temporaryDirectory
        let offered = [
            ExtensionImport.Candidate(id: "on", folder: folder, manifest: manifest, isEnabled: true),
            ExtensionImport.Candidate(id: "off", folder: folder, manifest: manifest, isEnabled: false),
            ExtensionImport.Candidate(id: "had", folder: folder, manifest: manifest, isEnabled: true),
        ]
        #expect(ExtensionImport.preselected(offered, installed: ["had"]) == ["on"])
        let picked = ExtensionImport.Candidate(id: "x", folder: folder, manifest: manifest, isEnabled: false, profiles: ["Default": false, "Profile 1": false])
        #expect(picked.sourceProfiles == ["Default", "Profile 1"], "picked though off: every profile that has it")
    }

    @Test func aCopyIsNamedByItsIDAndReplacesAnOlderOne() throws {
        let root = try Self.temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Extensions", isDirectory: true)
        let v1 = root.appendingPathComponent("src/1_0", isDirectory: true)
        try Self.write(#"{"name":"E","version":"1"}"#, to: v1.appendingPathComponent("manifest.json"))
        try Self.write("{}", to: v1.appendingPathComponent("_metadata/verified_contents.json"))
        let first = try ExtensionImport.copy(v1, id: "abcdef", into: store)
        #expect(first.lastPathComponent == "abcdef")
        #expect(!FileManager.default.fileExists(atPath: first.appendingPathComponent("_metadata").path), "the Web Store's hashes stay behind")
        #expect(ExtensionFolders.loadable(in: store).map(\.lastPathComponent) == ["abcdef"])

        let v2 = root.appendingPathComponent("src/2_0", isDirectory: true)
        try Self.write(#"{"name":"E","version":"2"}"#, to: v2.appendingPathComponent("manifest.json"))
        try ExtensionImport.copy(v2, id: "abcdef", into: store)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.path)
        #expect(names == ["abcdef"], "no staging folder or second copy left")
        let manifest = try String(contentsOf: store.appendingPathComponent("abcdef/manifest.json"), encoding: .utf8)
        #expect(manifest.contains(#""version":"2""#))
        #expect(throws: (any Error).self) { try ExtensionImport.copy(root.appendingPathComponent("gone"), id: "x", into: store) }
    }

    @Test func theResultSaysWhatComesIn() {
        #expect(ExtensionImport.summary(imported: 0, failed: []) == nil)
        #expect(ExtensionImport.summary(imported: 1, failed: []) == "1 extension comes in when Cra restarts.")
        #expect(ExtensionImport.summary(imported: 2, failed: ["A", "B"]) == "2 extensions come in when Cra restarts. Cra couldn’t copy A, B.")
    }
}
