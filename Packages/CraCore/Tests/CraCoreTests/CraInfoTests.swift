import CraCore
import Testing

/// Copy Cra Info's text, which the Mac and Windows both copy.
struct CraInfoTests {
    @Test func appLineNamesTheVersionAndBuild() {
        #expect(CraInfo.appLine(version: "1.2.3", build: "456") == "Cra 1.2.3 (456)")
        #expect(CraInfo.appLine(version: "1.2.3", build: "1.2.3") == "Cra 1.2.3")
        #expect(CraInfo.appLine(version: "1.2.3", build: nil) == "Cra 1.2.3")
        #expect(CraInfo.appLine(version: nil) == "Cra")
        #expect(CraInfo.appLine(version: "") == "Cra")
        #expect(CraInfo.appLine(version: "0.0.0", build: "") == "Cra")
    }

    @Test func windowsLineTakesTheBuildForTheName() {
        #expect(CraInfo.windowsLine(build: 26200, displayVersion: "25H2", revision: 9457) == "Windows 11 25H2 (build 26200.9457)")
        #expect(CraInfo.windowsLine(build: 22000, displayVersion: "21H2", revision: nil) == "Windows 11 21H2 (build 22000)")
        #expect(CraInfo.windowsLine(build: 19045, displayVersion: "22H2", revision: 5737) == "Windows 10 22H2 (build 19045.5737)")
        #expect(CraInfo.windowsLine(build: 19041, displayVersion: nil, revision: nil) == "Windows 10 (build 19041)")
        #expect(CraInfo.windowsLine(build: 19041, displayVersion: "", revision: 1) == "Windows 10 (build 19041.1)")
    }

    @Test func textIsOneLineEach() {
        let text = CraInfo.text(app: "Cra", engine: EngineVersion.label(chromium: "156.0.1.2", cef: "156.0.26"),
                                system: "Windows 11 25H2 (build 26200.9457)")
        #expect(text == "Cra\nChromium 156.0.1.2 · CEF 156.0.26\nWindows 11 25H2 (build 26200.9457)")
    }

    @Test func helpCommandsAreInTheWindowsCommandBar() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        for id in ["revealData", "copyAppInfo", "languageSettings", "taskManager", "cast", "essentialShortcuts"] {
            #expect(windows[id]?.inCommandBar == true, "\(id)")
            #expect(windows[id]?.shortcuts == [], "\(id)")
        }
    }
}
