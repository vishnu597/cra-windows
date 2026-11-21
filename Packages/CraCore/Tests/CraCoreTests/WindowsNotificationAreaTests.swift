import CraCore
import Testing

/// Settings ▸ Advanced ▸ "Keep Cra in the notification area" (#231), Windows' "Keep Cra in the menu
/// bar": closing the last window is Cra's own Quit there (WindowList.noWindowsLeft and
/// confirmQuit), and the icon's menu is the Mac menu bar item's.
struct WindowsNotificationAreaTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231"))
    func closingTheLastWindowStaysOnlyWithTheSettingOn() {
        #expect(MenuBarMode.lastWindowCloses(enabled: true) == .stayInMenuBar)
        #expect(MenuBarMode.lastWindowCloses(enabled: false) == .quit)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231"))
    func theIconsQuitIsARealQuitAndAsksAsClosingDoes() {
        #expect(MenuBarMode.outcome(enabled: true, source: .menuBarItem) == .quit)
        #expect(QuitPrompt.on(source: .menuBarItem, downloadsRunning: true, warnBeforeQuitting: false) == .downloadsInProgress)
        #expect(QuitPrompt.on(source: .menuBarItem, downloadsRunning: false, warnBeforeQuitting: true) == .confirmQuit)
        #expect(QuitPrompt.on(source: .menuBarItem, downloadsRunning: false, warnBeforeQuitting: false) == .none)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231"))
    func theMenuListsTheMacsCommandsAndEachHasAWindowsShortcut() {
        #expect(MenuBarMode.menuCommands == [["newWindow", "newIncognitoWindow", "newLittleWindow"], ["settings"]])
        let windows = KeyBindingDefaults.windowsShortcuts
        for id in MenuBarMode.menuCommands.joined() {
            #expect(windows[id]?.isEmpty == false, "\(id) has a key on Windows")
        }
    }
}
