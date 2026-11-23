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
}
