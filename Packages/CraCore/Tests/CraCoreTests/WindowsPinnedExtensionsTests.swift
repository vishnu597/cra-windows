import CraCore
import Foundation
import Testing

/// Windows' extension pins: the Site Control Center's badge pins or unpins in the page's profile
/// (pinned-extensions.json, the Mac's format), and the toolbar shows a button for each pin that
/// can run.
struct WindowsPinnedExtensionsTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func theToolbarShowsTheProfilesPinsThatCanRun() {
        var pins = PinnedExtensions(shared: ["ublock", "gone", "off"])
        #expect(pins.toolbarIDs(inProfile: "Default", enabled: ["ublock", "dark"]) == ["ublock"], "turned off or removed: no button")
        pins.setPinned("dark", true, inProfile: "Profile 2")
        #expect(pins.toolbarIDs(inProfile: "Profile 2", enabled: ["ublock", "dark"]) == ["ublock", "dark"])
        #expect(pins.toolbarIDs(inProfile: "Default", enabled: ["ublock", "dark"]) == ["ublock"], "another profile keeps its own")
    }

    /// The sidebar's address pill while the toolbar is hidden (BrowserWindow.syncPillPins): the
    /// pins go before the sliders while they leave the address 120 DIPs, else none show there.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/226"))
    func theAddressPillShowsThePinsWhileTheAddressKeepsItsRoom() {
        let three = ToolbarComposition.urlFieldAccessories(pinnedExtensions: ["a", "b", "c"], fieldWidth: 224)
        #expect(three.filter { if case .pinnedExtension = $0 { true } else { false } }.count == 3)
        let four = ToolbarComposition.urlFieldAccessories(pinnedExtensions: ["a", "b", "c", "d"], fieldWidth: 224)
        #expect(!four.contains(.pinnedExtension("a")), "224 − 4 × 28 leaves the address less than 120")
    }

    @Test func aPinSavedTwiceShowsOneButton() {
        let pins = PinnedExtensions(shared: ["a", "b", "a"])
        #expect(pins.toolbarIDs(inProfile: "Default", enabled: ["a", "b"]) == ["a", "b"])
    }

    @Test func pinsSaveInTheMacsFormat() throws {
        var pins = PinnedExtensions(shared: ["a"])
        let shared = String(decoding: try JSONEncoder().encode(pins), as: UTF8.self)
        #expect(shared == "[\"a\"]", "no profile of its own: the plain array")
        pins.setPinned("b", true, inProfile: "Default")
        let back = try JSONDecoder().decode(PinnedExtensions.self, from: try JSONEncoder().encode(pins))
        #expect(back == pins)
    }
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131"))
    func anImportBringsTheSourceBrowsersPins() throws {
        let prefs = Data(#"{"extensions":{"pinned_extensions":["ublock","dark"]},"other":1}"#.utf8)
        #expect(PinnedExtensions.chromiumPins(preferences: prefs) == ["ublock", "dark"])
        #expect(PinnedExtensions.chromiumPins(preferences: Data("{}".utf8)) == nil)

        var pins = PinnedExtensions()
        pins.seedImport(["Default": ["ublock"], "Profile 1": ["x"]], map: ImportProfileMap(), hasSavedPins: false)
        #expect(pins == PinnedExtensions(shared: ["ublock"]), "no profiles bound: the source's Default only")

        var kept = PinnedExtensions(shared: ["mine"])
        kept.seedImport(["Default": ["ublock"]], map: ImportProfileMap(), hasSavedPins: true)
        #expect(kept == PinnedExtensions(shared: ["mine"]), "Cra's own pins stay")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/131"))
    func eachProfileTheImportMadeGetsItsSourcesPins() {
        var pins = PinnedExtensions()
        let map = ImportProfileMap(folders: ["Default": "Default", "Profile 3": "Profile 9"])
        pins.seedImport(["Default": ["a"], "Profile 3": ["b", "c"]], map: map, hasSavedPins: false)
        #expect(pins.ids(inProfile: "Default") == ["a"])
        #expect(pins.ids(inProfile: "Profile 9") == ["b", "c"])
        #expect(pins.ids(inProfile: "Profile 4") == ["a"], "a profile the import didn't touch shows the shared list")

        var own = PinnedExtensions(shared: [], profiles: ["Profile 9": ["z"]])
        own.seedImport(["Profile 3": ["b"]], map: map, hasSavedPins: true)
        #expect(own.ids(inProfile: "Profile 9") == ["z"], "a profile's own list stays")
    }
}
