import CraCore
import Testing

/// View ▸ Appearance (Automatic, Light, Dark), which the Windows app runs from the command bar.
struct WindowsWebsiteAppearanceTests {
    @Test func eachCommandPicksItsAppearance() {
        #expect(WebsiteAppearance(commandID: "appearanceAutomatic") == .automatic)
        #expect(WebsiteAppearance(commandID: "appearanceLight") == .light)
        #expect(WebsiteAppearance(commandID: "appearanceDark") == .dark)
        #expect(WebsiteAppearance(commandID: "appearance") == nil)
        #expect(WebsiteAppearance(commandID: "newTab") == nil)
        for appearance in WebsiteAppearance.allCases {
            #expect(WebsiteAppearance(commandID: appearance.commandID) == appearance)
        }
    }

    @Test func theCommandsAreInTheWindowsCommandBarWithoutKeys() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for appearance in WebsiteAppearance.allCases {
            #expect(windows[appearance.commandID]?.inCommandBar == true, "\(appearance)")
            #expect(windows[appearance.commandID]?.shortcuts == [], "\(appearance)")
        }
    }

    @Test func chromiumTakesTheSystemsLightOrDark() {
        #expect(WebsiteAppearance.allCases.map(\.chromiumMode) == [0, 1, 2])
    }
}
