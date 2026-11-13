import CraCore
import Foundation
import Testing

/// The extensions a Chromium profile holds, as the Extensions menu lists them (Windows) and the
/// Mac's ExtensionStore and importer read them.
struct InstalledExtensionsTests {
    /// A profile folder with a Web Store install and an unpacked one, written to a temporary folder.
    private struct Profile {
        let dir: URL
        let unpacked: URL

        init() throws {
            let fm = FileManager.default
            dir = fm.temporaryDirectory.appendingPathComponent("cra-installed-\(UUID().uuidString)", isDirectory: true)
            unpacked = dir.appendingPathComponent("Unpacked", isDirectory: true)
            try write(#"{"name":"Store","version":"2.0","action":{"default_popup":"popup.html","default_icon":{"16":"a16.png","32":"a32.png"}},"icons":{"48":"i48.png","128":"i128.png"}}"#,
                      to: dir.appendingPathComponent("Extensions/store/2.0/manifest.json"))
            try write(#"{"name":"__MSG_name__","description":"__MSG_desc__","default_locale":"de","version":"1","options_ui":{"page":"options.html"},"icons":{"16":"x.png"}}"#,
                      to: unpacked.appendingPathComponent("manifest.json"))
            try write(#"{"name":{"message":"Entpackt"},"desc":{"message":"Beschreibung"}}"#,
                      to: unpacked.appendingPathComponent("_locales/de/messages.json"))
            try write(#"{"name":"A Theme","version":"1","theme":{}}"#, to: dir.appendingPathComponent("Extensions/theme/1/manifest.json"))
        }

        func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func remove() { try? FileManager.default.removeItem(at: dir) }
    }

    @Test func webStoreAndUnpackedInstallsAreListedByName() throws {
        let p = try Profile()
        defer { p.remove() }
        let settings: [String: Any] = [
            "storeid": ["location": 1, "path": "store/2.0", "disable_reasons": [Int]()],
            "unpackedid": ["location": 4, "path": p.unpacked.path],
            "themeid": ["location": 1, "path": "theme/1"],
            "pdf": ["location": 5, "path": "/component"],
            "avg": ["location": 6, "path": "store/2.0", "disable_reasons": [8192]],
            "missing": ["location": 1, "path": "gone/1"],
            "noise": "not a dictionary",
        ]
        let listed = InstalledExtensions.installed(settings: settings, inProfile: p.dir)
        #expect(listed.map(\.id) == ["unpackedid", "storeid"], "Entpackt before Store; no theme, component, external or missing folder")
        let unpacked = try #require(listed.first)
        #expect(unpacked.manifest.name == "Entpackt" && unpacked.manifest.description == "Beschreibung", "messages from the default locale")
        #expect(unpacked.manifest.optionsPath == "options.html" && unpacked.manifest.popupPath == nil)
        #expect(unpacked.folder.standardizedFileURL == p.unpacked.standardizedFileURL, "an absolute path is the folder itself")
        let store = listed[1]
        #expect(store.folder.standardizedFileURL == p.dir.appendingPathComponent("Extensions/store/2.0").standardizedFileURL,
                "a relative path sits in the profile's Extensions")
        #expect(store.isEnabled && store.manifest.version == "2.0" && store.manifest.popupPath == "popup.html")
        #expect(store.manifest.iconFiles(points: 16) == ["a16.png", "a32.png"], "the action's icons first")
        #expect(unpacked.manifest.iconFiles(points: 16) == ["x.png"], "else the extension's")
    }

    @Test func otherLocationsCanBeAskedFor() throws {
        let p = try Profile()
        defer { p.remove() }
        let settings: [String: Any] = ["cmd": ["location": 8, "path": p.unpacked.path]]
        #expect(InstalledExtensions.installed(settings: settings, inProfile: p.dir).isEmpty)
        #expect(InstalledExtensions.installed(settings: settings, inProfile: p.dir, locations: [8]).map(\.id) == ["cmd"])
    }

    /// The external installs other software registers for Chrome (AVG's, on the test PC) wait for
    /// approval turned off; Manifest V2 alone doesn't turn an extension off in Cra (#228).
    @Test func whatCountsAsTurnedOff() {
        #expect(InstalledExtensions.isDisabled(["disable_reasons": [8192]]), "an external install waiting for approval")
        #expect(InstalledExtensions.isDisabled(["disable_reasons": [1]]), "turned off in chrome://extensions")
        #expect(!InstalledExtensions.isDisabled(["disable_reasons": [InstalledExtensions.unsupportedManifestVersion]]), "only Manifest V2")
        #expect(!InstalledExtensions.isDisabled(["disable_reasons": [Int]()]))
        #expect(InstalledExtensions.isDisabled(["state": 0]), "older Chromium")
        #expect(!InstalledExtensions.isDisabled(["state": 1]))
        let settings: [String: Any] = ["a": ["disable_reasons": [1]], "b": ["state": 1], "c": 3]
        #expect(InstalledExtensions.disabledIDs(settings: settings) == ["a"])
    }

    @Test func settingsComeFromBothFilesOrTheLivePref() throws {
        let p = try Profile()
        defer { p.remove() }
        try p.write(#"{"extensions":{"settings":{"a":{"location":1},"b":{"location":1}}}}"#, to: p.dir.appendingPathComponent("Preferences"))
        try p.write(#"{"extensions":{"settings":{"b":{"location":4}}}}"#, to: p.dir.appendingPathComponent("Secure Preferences"))
        let files = InstalledExtensions.settings(inProfile: p.dir)
        #expect(Set(files.keys) == ["a", "b"])
        #expect((files["b"] as? [String: Any])?["location"] as? Int == 4, "Secure Preferences wins")
        #expect(InstalledExtensions.settings(inProfile: p.dir.appendingPathComponent("none")).isEmpty)
        let live = InstalledExtensions.settings(json: Data(#"{"c":{"location":1}}"#.utf8))
        #expect(Set(live.keys) == ["c"], "Chromium's live pref is the dictionary itself")
        #expect(InstalledExtensions.settings(json: Data("not json".utf8)).isEmpty)
    }

    @Test func windowsPathsAreAbsoluteToo() {
        #expect(InstalledExtensions.isAbsolute(#"C:\Users\me\ext"#) && InstalledExtensions.isAbsolute("D:/ext"))
        #expect(InstalledExtensions.isAbsolute(#"\\server\share\ext"#) && InstalledExtensions.isAbsolute("/Users/me/ext"))
        #expect(!InstalledExtensions.isAbsolute("abcd/1.0_0") && !InstalledExtensions.isAbsolute("C:") && !InstalledExtensions.isAbsolute("1:/x"))
    }

    @Test func aManifestWithoutAResolvableNameUsesTheFallback() {
        let folder = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let m = ExtensionManifest(manifest: ["name": "__MSG_x__", "description": "__MSG_y__", "app": [:],
                                             "browser_action": ["default_popup": "", "default_icon": "b.png"],
                                             "options_page": "o.html", "key": "KEY"],
                                  folder: folder, fallbackName: "abcd")
        #expect(m.name == "abcd" && m.description.isEmpty && m.isThemeOrApp)
        #expect(m.popupPath == nil, "an empty popup is none")
        #expect(m.optionsPath == "o.html" && m.key == "KEY" && m.actionIcons == ["16": "b.png"])
        #expect(ExtensionManifest(folder: folder, fallbackName: "x") == nil, "no manifest")
        #expect(ExtensionManifest.localized("plain", manifest: [:], folder: folder) == "plain")
        #expect(ExtensionManifest.localized("__MSG_gone__", manifest: [:], folder: folder) == "__MSG_gone__")
    }

    /// #41 and #22: the Windows Extensions menu has no page to hang Chrome's popup from, so a
    /// click opens the popup page in a window of its own, else the options page or Chrome's
    /// details page in a tab, and never runs an extension that's off.
    @Test func aMenuClickWithoutAPage() {
        typealias E = ExtensionLaunch.Extension
        let all = [E(id: "pop", popupPath: "p.html", optionsPath: "o.html"), E(id: "opt", optionsPath: "o.html"),
                   E(id: "bare"), E(id: "off", popupPath: "p.html", enabled: false)]
        #expect(ExtensionLaunch.decide("pop", available: all, hasPage: false) == .popupWindow(url: "chrome-extension://pop/p.html"))
        #expect(ExtensionLaunch.decide("opt", available: all, hasPage: false) == .openTab(url: "chrome-extension://opt/o.html"))
        #expect(ExtensionLaunch.decide("bare", available: all, hasPage: false) == .openTab(url: "chrome://extensions/?id=bare"))
        #expect(ExtensionLaunch.decide("off", available: all, hasPage: false) == .nothing)
        #expect(ExtensionLaunch.decide("gone", available: all, hasPage: false) == .nothing)
        #expect(ExtensionLaunch.decide("pop", available: all, hasPage: true) == .runAction)
        #expect(ExtensionLaunch.fallback(E(id: "off", enabled: false)) == .nothing)
    }
}
