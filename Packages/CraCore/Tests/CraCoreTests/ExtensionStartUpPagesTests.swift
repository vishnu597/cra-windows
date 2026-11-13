import CraCore
import Foundation
import Testing

/// Welcome pages from Cra's own extensions, which Chromium treats as new on every launch.
struct ExtensionStartUpPagesTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// PR #42's PC test: AdBlock, imported into Cra's folder, opened "AdBlock is now installed!"
    /// as a new tab on every launch. Only the launch after it arrived may open it.
    @Test func aKnownExtensionsWelcomePageIsDroppedAfterLaunch() {
        let pages = ExtensionStartUpPages(launchedAt: start, installed: ["adblock"], welcomed: ["adblock"])
        #expect(!pages.hasNewExtension)
        #expect(pages.drops(at: start.addingTimeInterval(2), isOpen: false))
        #expect(!pages.drops(at: start.addingTimeInterval(11), isOpen: false), "later pages are the extension's own doing")
    }

    @Test func aNewExtensionOpensItsPageOnce() {
        let pages = ExtensionStartUpPages(launchedAt: start, installed: ["adblock", "new"], welcomed: ["adblock"])
        #expect(pages.hasNewExtension)
        #expect(!pages.drops(at: start.addingTimeInterval(2), isOpen: false))
        #expect(pages.drops(at: start.addingTimeInterval(2), isOpen: true), "one already open isn't opened again")
        #expect(!ExtensionStartUpPages(launchedAt: start, installed: [], welcomed: ["gone"]).hasNewExtension,
                "a removed extension makes nothing new")
    }

    @Test func eachLaunchRemembersItsExtensions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-startup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ExtensionStartUpPages.launch(at: start, installed: ["b", "a"], directory: dir).hasNewExtension, "the first launch with them")
        #expect(!ExtensionStartUpPages.launch(at: start, installed: ["a", "b"], directory: dir).hasNewExtension, "the next one knows them")
        #expect(ExtensionStartUpPages.launch(at: start, installed: ["a", "b", "c"], directory: dir).hasNewExtension)
        let saved = try String(contentsOf: dir.appendingPathComponent(ExtensionStartUpPages.fileName), encoding: .utf8)
        #expect(saved == #"["a","b","c"]"#)
    }
}
