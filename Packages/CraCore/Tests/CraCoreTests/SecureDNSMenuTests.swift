import CraCore
import Testing

/// Settings ▸ Privacy ▸ Secure DNS as the Windows app draws it: the Mac's rows and footnote.
struct SecureDNSMenuTests {
    @Test func theMenuListsTheMacsRowsInOrder() {
        let titles = SecureDNSChoice.menuGroups.map { $0.map(\.title) }
        #expect(titles.first == ["Automatic", "Off"])
        #expect(titles[1] == SecureDNSProvider.all.map(\.name))
        #expect(titles.last == ["Custom…"])
    }

    @Test func theFootnoteSaysWhoSetsIt() {
        let automatic = SecureDNS(mode: "automatic", templates: "")
        #expect(automatic.footnote(managed: false) == automatic.summary)
        #expect(automatic.footnote(managed: true) == "Your organization sets secure DNS. " + automatic.summary)
        #expect(SecureDNS(mode: "", templates: "").footnote(managed: false) == nil, "nothing set yet")
    }
}
