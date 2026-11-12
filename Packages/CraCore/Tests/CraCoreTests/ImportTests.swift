import CraCore
import Foundation
import Testing

/// The importers both apps share (Arc's files, Chromium bookmarks and sessions, applying a plan),
/// on the Mac's fixtures in Tests/Fixtures so the Mac's store tests and these read the same files.
@MainActor
struct ImportTests {
    /// The repository's Tests/Fixtures.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests", isDirectory: true).appendingPathComponent("Fixtures", isDirectory: true)
    static let arc = fixtures.appendingPathComponent("Arc", isDirectory: true)

    private func arcPlan(_ preferences: ArcImporter.Preferences = .init()) throws -> ImportPlan {
        try ArcImporter.plan(supportDir: Self.arc, preferences: preferences)
    }

    @Test func readsArcsSpacesFavoritesAndArchive() throws {
        #expect(ArcImporter.isAvailable(in: Self.arc))
        let plan = try arcPlan()
        #expect(plan.spaces.map(\.title) == ["Home", "Work"], "both spaces come over in Arc's order")
        #expect(plan.spaces.map(\.emoji) == ["🏠", "💼"], "emoji_v2 and the older numeric emoji both read")
        let home = plan.spaces[0], work = plan.spaces[1]
        #expect(home.favorites.compactMap(\.url) == ["https://example.com/mail", "https://example.com/calendar"],
                "the profile's top apps become the space's favorites")
        #expect(home.pinned.count == 1 && home.pinned[0].isFolder && home.pinned[0].customTitle == "Reading" && home.pinned[0].children.count == 2)
        #expect(home.pinned[0].children[1].customTitle == "My blog", "a renamed tab keeps its custom title")
        #expect(home.today.count == 3)
        #expect(work.pinned.isEmpty && work.today.count == 1 && work.today[0].isFolder && work.today[0].children.count == 2,
                "a split view is flattened into a folder of its tabs")
        #expect(plan.archive.map(\.pageTitle) == ["Old two", "Old one"], "archived tabs are newest first")
        #expect(plan.archive.map(\.reason) == [.manual, .auto] && plan.archive.map(\.spaceTitle) == ["Work", "Home"])
        #expect(plan.settings.sidebarWidth == 280)
        #expect(plan.spaces[0].profile == nil && plan.spaces[1].profile == ImportedProfile(folder: "Profile 2", name: "Client"))
    }

    @Test func takesArcsPreferencesFromTheApp() throws {
        #expect(try arcPlan().settings.showToolbar == nil)
        let plan = try arcPlan(ArcImporter.Preferences(autoArchive: "sevenDays", showsToolbar: true, showsFullURL: false))
        #expect(plan.settings.autoArchive == .sevenDays)
        #expect(plan.settings.showToolbar == true && plan.settings.toolbarShowsFullURL == false)
    }

    @Test func missingArcIsNotFound() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(!ArcImporter.isAvailable(in: nowhere))
        #expect(throws: ImportError.notFound("Arc")) { try ArcImporter.plan(supportDir: nowhere, preferences: .init()) }
    }

    @Test func arcFaviconsAreNamedByTheItemsMD5() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = dir.appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ArcImporter.faviconFile(forItemID: "ABCDEF-1234", in: dir) == nil)
        try Data([1]).write(to: cache.appendingPathComponent("a02e184916f9b5fa20ae29aec6d1613c"))
        #expect(ArcImporter.faviconFile(forItemID: "ABCDEF-1234", in: dir)?.hasSuffix("a02e184916f9b5fa20ae29aec6d1613c") == true)
    }

    @Test func md5MatchesRFC1321() {
        #expect(MD5.hex(Data()) == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(MD5.hex(Data("abc".utf8)) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(MD5.hex(Data("The quick brown fox jumps over the lazy dog".utf8)) == "9e107d9d372bb6826bd81d3542a419d6")
        #expect(MD5.hex(Data(repeating: 0x61, count: 1_000)) == "cabe45dcc9ae5b66ba86600cca6b8ba8")
    }

    @Test func readsAChromiumProfile() {
        let profile = Self.fixtures.appendingPathComponent("Chromium/Default", isDirectory: true)
        let tabs = ChromiumImporter.openTabs(profile: profile)
        #expect(tabs.map(\.url) == ["https://example.com/one", "https://example.com/two-b"],
                "open tabs: the selected navigation of each, closed tabs and chrome:// pages left out, in window order")
        #expect(tabs.map(\.pageTitle) == ["One", "Two, then Ü"])
        let marks = ChromiumImporter.bookmarks(profile: profile)
        #expect(marks.bar.map(\.pageTitle) == ["Docs", "Reading"] && marks.bar[1].children.map(\.url) == ["https://example.com/read"])
        #expect(marks.other.map(\.url) == ["https://example.com/other"])
        #expect(ChromiumImporter.parseSession(Data("SNSS".utf8) + Data([4, 0, 0, 0]) + Data(repeating: 1, count: 16)).isEmpty,
                "an encrypted session (version 4) gives nothing rather than garbage")

        let plan = try? ChromiumImporter.plan(browser: "Chrome", userData: Self.fixtures.appendingPathComponent("Chromium", isDirectory: true))
        #expect(plan?.spaces.map(\.title) == ["Chrome"], "one profile: the space is named after the browser")
        #expect(plan?.spaces.first?.pinned.last?.customTitle == "Other Bookmarks")
        #expect(plan?.spaces.first?.today.count == 2)
    }

    @Test func ordersChromiumProfilesAsTheBrowserDoes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Profile 10", "Profile 2", "Default", "System Profile", "Guest Profile"] {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: dir.appendingPathComponent("Bookmarks"))
        }
        let state = #"{"profile":{"info_cache":{"Profile 2":{"name":"Work"}}}}"#
        try Data(state.utf8).write(to: root.appendingPathComponent("Local State"))
        let profiles = ChromiumImporter.profiles(userData: root)
        #expect(profiles.map(\.id) == ["Default", "Profile 2", "Profile 10"])
        #expect(profiles.map(\.name) == ["Default", "Work", "Profile 10"])
        #expect(throws: ImportError.notFound("Edge")) { try ChromiumImporter.plan(browser: "Edge", profiles: []) }
    }

    @Test func applyingAPlanAddsSpacesProfilesAndFavicons() throws {
        let fixture = StoreFixture()
        let favicons = fixture.directory.appendingPathComponent("Favicons", isDirectory: true)
        try FileManager.default.createDirectory(at: favicons, withIntermediateDirectories: true)
        let icon = fixture.directory.appendingPathComponent("icon.png")
        try Data([0x89, 0x50]).write(to: icon)
        var plan = try arcPlan()
        plan.spaces[0].pinned[0].children[0].faviconPath = icon.path
        let result = fixture.store.apply(plan, includeArchive: true, includeSettings: true, favicons: favicons)
        #expect(result.spaces == 2 && result.archived == 2)
        let titles = fixture.store.orderedSpaces.map(\.title)
        #expect(titles.contains("Home") && titles.contains("Work"))
        #expect(fixture.sound)
        let work = try #require(fixture.store.orderedSpaces.first { $0.title == "Work" })
        #expect(fixture.store.profiles.map(\.name) == ["Client"] && work.profileID == fixture.store.profiles.first?.id)
        let url = try #require(plan.spaces[0].pinned[0].children[0].url)
        let key = try #require(FaviconKey.key(for: url))
        #expect(FileManager.default.fileExists(atPath: favicons.appendingPathComponent(FaviconKey.fileName(key)).path),
                "a favicon Arc cached is copied into Cra's favicon folder")

        let again = fixture.store.apply(plan, includeArchive: false, includeSettings: false, favicons: nil)
        #expect(again.spaces == 2 && fixture.store.profiles.count == 1, "importing again reuses the profile of the same name")
        #expect(fixture.store.orderedSpaces.map(\.title).contains("Home 2"), "a taken title gets a number")
    }

    @Test func findsBrowsersInWindowsFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = WindowsImportSource.Folders(local: root.appendingPathComponent("Local", isDirectory: true),
                                                  roaming: root.appendingPathComponent("Roaming", isDirectory: true))
        let fm = FileManager.default
        #expect(WindowsImportSource.available(in: folders).isEmpty)

        // Edge with a profile, Opera keeping its one profile in its own folder, Arc's package.
        let edge = folders.local.appendingPathComponent("Microsoft/Edge/User Data/Default", isDirectory: true)
        try fm.createDirectory(at: edge, withIntermediateDirectories: true)
        try fm.copyItem(at: Self.fixtures.appendingPathComponent("Chromium/Default/Bookmarks"), to: edge.appendingPathComponent("Bookmarks"))
        let opera = folders.roaming.appendingPathComponent("Opera Software/Opera Stable", isDirectory: true)
        try fm.createDirectory(at: opera, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: opera.appendingPathComponent("History"))
        let arcParent = folders.local.appendingPathComponent("Packages/TheBrowserCompany.Arc_ttt1ap7aakyb4/LocalCache/Local", isDirectory: true)
        try fm.createDirectory(at: arcParent, withIntermediateDirectories: true)
        try fm.copyItem(at: Self.arc, to: arcParent.appendingPathComponent("Arc", isDirectory: true))
        // Chrome's folder with no profile data is no source.
        try fm.createDirectory(at: folders.local.appendingPathComponent("Google/Chrome/User Data/Default", isDirectory: true), withIntermediateDirectories: true)

        let available = WindowsImportSource.available(in: folders)
        #expect(available.map(\.id) == ["arc", "edge", "opera"], "in the Mac's order, only those with data")
        #expect(WindowsImportSource.arc.folder(in: folders)?.lastPathComponent == "Arc")
        #expect(available.first { $0.id == "opera" }?.profiles(in: folders).map(\.dir.lastPathComponent) == ["Opera Stable"])

        let arcPlan = try WindowsImportSource.arc.plan(in: folders)
        #expect(arcPlan.spaces.map(\.title) == ["Home", "Work"] && arcPlan.settings.showToolbar == nil)
        let edgePlan = try #require(available.first { $0.id == "edge" }).plan(in: folders)
        #expect(edgePlan.source == "Edge" && edgePlan.spaces.map(\.title) == ["Edge"])
        #expect(edgePlan.spaces[0].pinned.map(\.pageTitle) == ["Docs", "Reading", "Other Bookmarks"])
    }

    @Test func readsWindowsFoldersFromTheEnvironment() {
        #expect(WindowsImportSource.Folders(environment: [:]) == nil)
        let folders = WindowsImportSource.Folders(environment: ["LOCALAPPDATA": "/u/AppData/Local", "APPDATA": "/u/AppData/Roaming"])
        #expect(folders?.local.lastPathComponent == "Local" && folders?.roaming.lastPathComponent == "Roaming")
    }

    @Test func summarisesAnImport() {
        var result = SidebarStore.ImportResult()
        #expect(result.summary(from: "Edge") == "Nothing new to import from Edge")
        result.spaces = 1
        #expect(result.summary(from: "Edge") == "Imported 1 space from Edge")
        result.tabs = 31
        #expect(result.summary(from: "Edge") == "Imported 1 space and 31 tabs from Edge")
        result.spaces = 2
        result.folders = 1
        result.archived = 4
        #expect(result.summary(from: "Arc") == "Imported 2 spaces, 31 tabs, 1 folder and 4 archived tabs from Arc")
    }
}
