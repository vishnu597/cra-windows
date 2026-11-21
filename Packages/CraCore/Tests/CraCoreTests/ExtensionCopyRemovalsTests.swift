import CraCore
import Foundation
import Testing

/// Remove in chrome://extensions takes an extension Cra loads from Extensions/ (an import, Add
/// Unpacked Extension…) out of that profile for good, not only until the next launch.
struct ExtensionCopyRemovalsTests {
    let path = "/Users/me/Library/Application Support/Cra/Extensions/abcdefghijklmnopabcdefghijklmnop"
    let id = "abcdefghijklmnopabcdefghijklmnop"
    var loaded: [String: Any] { [id: ["location": 8, "path": path]] }

    func removed(_ removals: inout ExtensionCopyRemovals, profile: String = "Default", _ settings: [String: Any]) -> Bool {
        removals.wasRemoved(folder: id, copyPath: path, extensionID: id, profile: profile, settings: settings)
    }

    @Test func removedAfterChromiumHadLoadedIt() {
        var removals = ExtensionCopyRemovals()
        #expect(!removed(&removals, profile: "Default", loaded))
        #expect(removed(&removals, profile: "Default", [:]),
                "its entry left the profile's live settings: Remove in chrome://extensions")
        #expect(!removed(&removals, profile: "Default", [:]),
                "reported once")
    }

    @Test func neverLoadedIsNotRemoved() {
        var removals = ExtensionCopyRemovals()
        #expect(!removed(&removals, profile: "Default", [:]),
                "a profile that has not loaded it yet (start-up, a bad manifest) removed nothing")
    }

    @Test func eachProfileOnItsOwn() {
        var removals = ExtensionCopyRemovals()
        _ = removed(&removals, profile: "Default", loaded)
        #expect(!removed(&removals, profile: "Profile 1", [:]))
        #expect(removed(&removals, profile: "Default", [:]))
    }

    @Test func replacedIsNotRemoved() {
        var removals = ExtensionCopyRemovals()
        _ = removed(&removals, profile: "Default", loaded)
        let store: [String: Any] = [id: ["location": 1, "from_webstore": true, "path": "\(id)/1.0_0"]]
        #expect(!removed(&removals, profile: "Default", store),
                "the Web Store's install took its place (#203)")
        #expect(!removed(&removals, profile: "Default", [id: ["location": 8, "path": path, "disable_reasons": [1]]]),
                "turned off is not removed")
    }

    @Test func foundByItsPathWhenTheIDDiffers() {
        // Chromium names a keyless copy after its real path; Cra may have read it through another.
        var removals = ExtensionCopyRemovals()
        let other = "ponmlkjihgfedcbaponmlkjihgfedcba"
        let settings: [String: Any] = [other: ["location": 8, "path": path + "/"]]
        #expect(!removed(&removals, profile: "Default", settings))
        #expect(removed(&removals, profile: "Default", [:]))
    }

    @Test func onlyItsOwnCommandLineInstallCounts() {
        var removals = ExtensionCopyRemovals()
        let elsewhere: [String: Any] = ["ponmlkjihgfedcbaponmlkjihgfedcba": ["location": 8, "path": "/Users/me/other"]]
        _ = removed(&removals, profile: "Default", elsewhere)
        let unpacked: [String: Any] = ["ponmlkjihgfedcbaponmlkjihgfedcba": ["location": 4, "path": path]]
        _ = removed(&removals, profile: "Default", unpacked)
        #expect(!removed(&removals, profile: "Default", [:]))
    }

    /// Windows' Chromium writes `C:\…` paths; a keyless copy is found by its path, whatever the case
    /// or the slashes.
    @Test func aWindowsCopyIsFoundByItsPath() {
        var removals = ExtensionCopyRemovals()
        let copy = #"C:\Users\Me\AppData\Local\Cra\Extensions\AdBlock"#
        let loaded: [String: Any] = ["gighmmpiobklfepjocnamgkkbiglidom": ["location": 8, "path": #"c:\users\me\appdata\local\cra\extensions\adblock\"#]]
        let first = removals.wasRemoved(folder: "AdBlock", copyPath: copy, extensionID: "", profile: "Default", settings: loaded)
        #expect(!first)
        let gone = removals.wasRemoved(folder: "AdBlock", copyPath: copy, extensionID: "", profile: "Default", settings: [:])
        #expect(gone, "removed in chrome://extensions")
    }

    @Test func aKeyedCopysIDIsChromiums() {
        #expect(ExtensionCopyRemovals.keyedID(base64Key: nil) == nil)
        #expect(ExtensionCopyRemovals.keyedID(base64Key: "not base64!") == nil)
        let id = ExtensionCopyRemovals.keyedID(base64Key: "AAAA")
        #expect(id?.count == 32)
        #expect(id?.allSatisfy { ("a"..."p").contains($0) } == true)
    }
}
