import CraCore
import Foundation
import Testing

/// Cra's own Extensions/ folder, which Settings ▸ Extensions adds to and --load-extension loads.
struct ExtensionFoldersTests {
    private static func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-ext-folders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func onlyFoldersWithAManifestLoadInNameOrder() throws {
        let dir = try Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.write("{}", to: dir.appendingPathComponent("b/manifest.json"))
        try Self.write("{}", to: dir.appendingPathComponent("a/manifest.json"))
        try Self.write("{}", to: dir.appendingPathComponent(".c.importing/manifest.json"))
        try Self.write("x", to: dir.appendingPathComponent("empty/readme.txt"))
        #expect(ExtensionFolders.loadable(in: dir).map(\.lastPathComponent) == ["a", "b"])
        #expect(ExtensionFolders.loadable(in: dir.appendingPathComponent("none")).isEmpty)
    }

    @Test func theSwitchSkipsPathsWithCommas() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Extensions", isDirectory: true)
        let a = dir.appendingPathComponent("a", isDirectory: true)
        let comma = dir.appendingPathComponent("x,y", isDirectory: true)
        let b = dir.appendingPathComponent("b", isDirectory: true)
        #expect(ExtensionFolders.commandLineValue([a, comma, b]) == a.path + "," + b.path)
        #expect(ExtensionFolders.commandLineValue([comma]) == nil)
        #expect(ExtensionFolders.commandLineValue(paths: [#"C:\Cra\Extensions\a"#, "", #"C:\x,y"#]) == #"C:\Cra\Extensions\a"#)
        #expect(ExtensionFolders.commandLineValue([]) == nil)
    }

    @Test func aTakenNameGetsANumber() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Extensions", isDirectory: true)
        let taken: Set<String> = ["ext", "ext-2"]
        let dest = ExtensionFolders.destination(for: dir.deletingLastPathComponent().appendingPathComponent("src/ext", isDirectory: true), in: dir) {
            taken.contains($0.lastPathComponent)
        }
        #expect(dest.lastPathComponent == "ext-3")
        #expect(ExtensionFolders.destination(for: dir.deletingLastPathComponent().appendingPathComponent("src/new", isDirectory: true), in: dir) { _ in false }
            .lastPathComponent == "new")
    }

    @Test func addingCopiesAnExtensionAndRefusesTheRest() throws {
        let root = try Self.temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Extensions", isDirectory: true)
        let src = root.appendingPathComponent("src/ext", isDirectory: true)
        try Self.write(#"{"name":"E","version":"1"}"#, to: src.appendingPathComponent("manifest.json"))
        try Self.write("js", to: src.appendingPathComponent("worker.js"))
        let first = try ExtensionFolders.add(folder: src, to: store)
        let second = try ExtensionFolders.add(folder: src, to: store)
        #expect(first.lastPathComponent == "ext" && second.lastPathComponent == "ext-2")
        #expect(FileManager.default.fileExists(atPath: first.appendingPathComponent("worker.js").path))
        #expect(ExtensionFolders.loadable(in: store).count == 2)

        let none = root.appendingPathComponent("src/none", isDirectory: true)
        try FileManager.default.createDirectory(at: none, withIntermediateDirectories: true)
        #expect(throws: ExtensionFolders.AddError.noManifest) { try ExtensionFolders.add(folder: none, to: store) }
        let theme = root.appendingPathComponent("src/theme", isDirectory: true)
        try Self.write(#"{"name":"T","theme":{}}"#, to: theme.appendingPathComponent("manifest.json"))
        #expect(throws: ExtensionFolders.AddError.themeOrApp) { try ExtensionFolders.add(folder: theme, to: store) }
        let broken = root.appendingPathComponent("src/broken", isDirectory: true)
        try Self.write("not json", to: broken.appendingPathComponent("manifest.json"))
        #expect(throws: ExtensionFolders.AddError.unreadableManifest) { try ExtensionFolders.add(folder: broken, to: store) }
        #expect(try ExtensionFolders.add(folder: theme, to: store, checkKind: false).lastPathComponent == "theme",
                "the Mac's pane copies any folder with a manifest")
        #expect(ExtensionFolders.AddError.noManifest.localizedDescription == "That folder has no manifest.json.")
    }

    @Test func anInstallFromTheFolderIsToldApart() {
        let root = FileManager.default.temporaryDirectory
        let dir = root.appendingPathComponent("Data", isDirectory: true).appendingPathComponent("Extensions", isDirectory: true)
        #expect(ExtensionFolders.contains(dir.appendingPathComponent("ext", isDirectory: true), directory: dir))
        #expect(ExtensionFolders.contains(root.appendingPathComponent("DATA/extensions/ext", isDirectory: true), directory: dir))
        #expect(!ExtensionFolders.contains(dir.appendingPathComponent("ext/sub", isDirectory: true), directory: dir))
        #expect(!ExtensionFolders.contains(root.appendingPathComponent("elsewhere/ext", isDirectory: true), directory: dir))
    }
}
