import CraCore
import Foundation
import Testing

/// cra:// links read as AppDelegate.handleInternalURL reads them on the Mac.
struct CraLinkTests {
    @Test func commandBar() {
        #expect(CraLink("cra://commandbar") == .commandBar(query: nil, editURL: false))
        #expect(CraLink("cra://commandbar?query=hello%20world") == .commandBar(query: "hello world", editURL: false))
        #expect(CraLink("cra://commandbar?mode=edit") == .commandBar(query: nil, editURL: true))
        #expect(CraLink("CRA://COMMANDBAR?query=x") == .commandBar(query: "x", editURL: false), "scheme and host in any case")
    }

    @Test func open() {
        let space = UUID()
        #expect(CraLink("cra://open?url=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1")
            == .open(url: "https://example.com/a?b=1", space: nil, background: false, little: false))
        #expect(CraLink("cra://open?url=https://example.com&space=\(space.uuidString)&background=1")
            == .open(url: "https://example.com", space: space, background: true, little: false))
        #expect(CraLink("cra://open?url=https://example.com&little=1&space=not-a-uuid")
            == .open(url: "https://example.com", space: nil, background: false, little: true))
        #expect(CraLink("cra://open") == nil, "nothing to open")
        #expect(CraLink("cra://open?url=") == nil)
    }

    @Test func scripting() {
        #expect(CraLink("cra://dismiss") == .dismiss)
        #expect(CraLink("cra://action/newTab") == .action("newTab"))
        #expect(CraLink("cra://action/") == .other("action"))
        #expect(CraLink("cra://navigate?url=https://example.com") == .navigate("https://example.com"))
        #expect(CraLink("cra://navigate") == nil)
        #expect(CraLink("cra://debug?quit=1") == .other("debug"))
    }

    @Test(arguments: ["https://example.com", "file:///C:/a.html", "craft://open?url=https://x", "not a link"])
    func notCraLinks(link: String) {
        #expect(CraLink(link) == nil)
    }
}
