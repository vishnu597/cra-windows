import CraCore
import Foundation
import Testing

/// Links from other apps: which a launch's command line carries and where each opens.
struct ExternalLinkTests {
    @Test func commandLineKeepsLinksAndFilesAndDropsSwitches() {
        let args = ["--single-argument", "https://example.com/a?b=1#c", "--", "-psn_0_123", "HTTP://EXAMPLE.ORG",
                    "cra://commandbar", "file:///C:/x.html", "not a link", "", "mailto:me@example.com"]
        #expect(ExternalLink.links(inArguments: args)
            == ["https://example.com/a?b=1#c", "HTTP://EXAMPLE.ORG", "cra://commandbar", "file:///C:/x.html"])
    }

    @Test func windowsPathsBecomeFileURLs() {
        #expect(ExternalLink.links(inArguments: [#"C:\Users\me\My Page.html"#]) == ["file:///C:/Users/me/My%20Page.html"])
        #expect(ExternalLink.fileURL(windowsPath: #"d:/docs/a#1?.htm"#) == "file:///d:/docs/a%231%3F.htm")
        #expect(ExternalLink.fileURL(windowsPath: #"\\server\share\x.html"#) == "file://server/share/x.html")
        #expect(ExternalLink.fileURL(windowsPath: #"C:\Users\me\café.html"#) == "file:///C:/Users/me/caf%C3%A9.html")
        #expect(ExternalLink.fileURL(windowsPath: "relative\\x.html") == nil)
        #expect(ExternalLink.fileURL(windowsPath: "/home/me/x.html") == nil)
    }

    @Test func routesPickLittleWindowOrSpace() {
        var settings = AppSettings()
        let work = UUID(), gone = UUID()
        settings.defaultLinkDestination = .littleWindowInUse
        settings.linkRoutes = [
            LinkRoute(match: .contains, text: "github.com", destination: .space(work)),
            LinkRoute(match: .contains, text: "old.example", destination: .space(gone)),
            .googleMeet,
        ]
        let exists: (UUID) -> Bool = { $0 == work }
        #expect(ExternalLink.target(for: "https://example.com", settings: settings, spaceExists: exists) == .littleWindow(space: nil))
        #expect(ExternalLink.target(for: "https://github.com/vishnu597", settings: settings, spaceExists: exists) == .space(work))
        // A route to a deleted space opens in the most recent one.
        #expect(ExternalLink.target(for: "https://old.example/x", settings: settings, spaceExists: exists) == .mostRecentSpace)
        #expect(ExternalLink.target(for: "https://meet.google.com/abc", settings: settings, spaceExists: exists) == .mostRecentSpace)
        settings.openExternalLinksInLittleWindow = false
        #expect(ExternalLink.target(for: "https://example.com", settings: settings, spaceExists: exists) == .mostRecentSpace)
    }

    @Test func otherAppsOnlyGetCrasUserFacingLinks() {
        let settings = AppSettings()
        let target = { (url: String, scripting: Bool) in ExternalLink.target(for: url, settings: settings, allowsScripting: scripting) { _ in true } }
        #expect(target("cra://commandbar", false) == .internalURL)
        #expect(target("cra://dismiss", false) == .internalURL)
        #expect(target("cra://open?url=https%3A%2F%2Fexample.com", false) == .internalURL)
        #expect(target("cra://open?url=file%3A%2F%2F%2Fetc%2Fpasswd", false) == .ignored)
        #expect(target("CRA://open?space=Work", false) == .ignored)
        #expect(target("cra://open?space=Work", true) == .internalURL)
    }

    @Test func littleWindowRoutesKeepOnlyExistingNamedSpaces() {
        var settings = AppSettings()
        let work = UUID(), gone = UUID()
        settings.linkRoutes = []
        settings.defaultLinkDestination = .littleWindow(space: work)
        let exists: (UUID) -> Bool = { $0 == work }
        #expect(ExternalLink.target(for: "https://example.com", settings: settings, spaceExists: exists) == .littleWindow(space: work))
        settings.defaultLinkDestination = .littleWindow(space: gone)
        #expect(ExternalLink.target(for: "https://example.com", settings: settings, spaceExists: exists) == .littleWindow(space: nil))
        settings.defaultLinkDestination = .littleWindowInUse
        #expect(ExternalLink.target(for: "https://example.com", settings: settings, spaceExists: exists) == .littleWindow(space: nil))
    }
}
