import CraCore
import Testing

/// Windows' native messaging hosts (Extensions ▸ Native messaging hosts): the other browsers'
/// registry entries copied into the key Cra's Chromium reads, each launch.
struct WindowsNativeMessagingTests {
    private let chrome = ["com.1password.1password": #"C:\1P\chrome.json"#, "com.openai.codexextension": #"C:\gpt.json"#]
    private let edge = ["com.1password.1password": #"C:\1P\edge.json"#, "com.bitwarden.desktop": #"C:\BW\edge.json"#]

    @Test func theOtherBrowsersHostsComeOverChromeFirst() {
        let plan = NativeMessagingMirror.plan(sources: [chrome, edge], present: [:], owned: [], manifestExists: { _ in true })
        #expect(plan.write == ["com.1password.1password": #"C:\1P\chrome.json"#, "com.bitwarden.desktop": #"C:\BW\edge.json"#])
        #expect(plan.owned == ["com.1password.1password", "com.bitwarden.desktop"])
        #expect(plan.remove.isEmpty)
    }

    @Test func aHostThatDrivesChromeStaysOut() {
        let plan = NativeMessagingMirror.plan(sources: [chrome], present: [:], owned: [], manifestExists: { _ in true })
        #expect(plan.write["com.openai.codexextension"] == nil)
    }

    @Test func anUninstalledAppsEntryGoesAndSomeoneElsesStays() {
        let present = ["com.bitwarden.desktop": #"C:\BW\edge.json"#, "org.mine.host": #"C:\mine.json"#]
        let plan = NativeMessagingMirror.plan(sources: [["org.mine.host": #"C:\other.json"#]], present: present,
                                              owned: ["com.bitwarden.desktop"], manifestExists: { _ in true })
        #expect(plan.remove == ["com.bitwarden.desktop"])
        #expect(plan.write.isEmpty, "the user's own entry isn't rewritten")
        #expect(plan.owned.isEmpty)
    }

    @Test func anEntryAlreadyRightIsLeftAndAMissingManifestIsSkipped() {
        let present = ["com.1password.1password": #"C:\1P\chrome.json"#]
        let plan = NativeMessagingMirror.plan(sources: [chrome, edge], present: present, owned: ["com.1password.1password"],
                                              manifestExists: { $0 != #"C:\BW\edge.json"# })
        #expect(plan.write.isEmpty)
        #expect(plan.owned == ["com.1password.1password"])
    }
}
