import CraCore
import Testing

/// Settings ▸ Advanced ▸ About on Windows: the title and what a click on it copies (the Mac's #461).
struct CraVersionWindowsTests {
    @Test func releaseBuildNamesItsVersionAndEngine() {
        #expect(CraVersion.windowsTitle(version: "0.2.1") == "Cra 0.2.1")
        #expect(CraVersion.windowsLine(version: "0.2.1", engine: "Chromium 142.0.7444.0 · CEF 142.0.0")
                == "Cra 0.2.1 · Chromium 142.0.7444.0 · CEF 142.0.0")
    }

    @Test func localBuildIsJustCra() {
        #expect(CraVersion.windowsTitle(version: "0.0.0") == "Cra", "Resources/Cra.rc's default")
        #expect(CraVersion.windowsTitle(version: nil) == "Cra")
        #expect(CraVersion.windowsLine(version: nil, engine: "") == "Cra")
    }
}
