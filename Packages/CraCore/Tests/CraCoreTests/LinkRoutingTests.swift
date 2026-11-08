import CraCore
import Foundation
import Testing

/// Air Traffic Control against what Arc 1.170 did with the same routes (26 Oct 2026, links handed
/// over with `open -g -a Arc`; docs/arc-reverse-engineering.md, "Air Traffic Control").
struct LinkRoutingTests {
    @Test(arguments: [
        // Case, scheme and a leading www. go on both sides.
        (LinkMatchStyle.contains, "https://example.com/atc-scheme", "http://example.com/atc-scheme", true),
        (.contains, "https://example.com/atc-scheme", "https://www.example.com/atc-scheme", true),
        (.contains, "ATC-CASE", "https://example.com/atc-case", true),
        // Contains also sees the query and the fragment.
        (.contains, "atc-order", "https://example.com/?x=atc-order", true),
        (.contains, "atc-recent", "https://example.com/#atc-recent", true),
        (.contains, "atc-missing", "https://example.com/other", false),
        // Is equal to: host and path only, trailing slashes dropped.
        (.equals, "example.com/atc-eq", "https://example.com/atc-eq?x=1", true),
        (.equals, "example.com/atc-eq", "https://example.com/atc-eq#frag", true),
        (.equals, "example.com/atc-eq", "http://www.EXAMPLE.com/atc-eq/", true),
        (.equals, "example.com/atc-eq", "https://example.com/atc-eq/more", false),
        // An empty route matches nothing.
        (.contains, "  ", "https://example.com/", false),
        (.equals, "", "https://example.com/", false),
    ])
    func matchesLikeArc(style: LinkMatchStyle, text: String, url: String, matches: Bool) {
        #expect(LinkRoute(match: style, text: text).matches(url) == matches)
    }

    @Test func firstMatchWinsElseTheDefault() {
        let work = UUID()
        var settings = AppSettings()
        settings.linkRoutes = [
            LinkRoute(match: .contains, text: "example.com", destination: .space(work)),
            LinkRoute(match: .contains, text: "example.com/call", destination: .littleWindow),
            .googleMeet,
        ]
        #expect(settings.destination(forExternalURL: "https://example.com/call") == .space(work))
        #expect(settings.destination(forExternalURL: "https://meet.google.com/abc") == .mostRecentSpace)
        #expect(settings.destination(forExternalURL: "https://other.test/") == .littleWindow, "no match: the default")
    }

    @Test func styles() {
        #expect(LinkMatchStyle.allCases.map(\.label) == ["Is equal to", "Contains"])
        #expect(LinkMatchStyle.allCases.map(\.id) == ["equals", "contains"])
        let route = LinkRoute()
        #expect(route.match == .contains && route.text.isEmpty && route.destination == .mostRecentSpace)
    }

    /// Peek's "other site": the registrable domain, with co.uk-style suffixes kept together.
    @Test(arguments: [
        ("https://mail.google.com/a", "google.com"),
        ("https://accounts.google.com/", "google.com"),
        ("https://Shop.Example.co.uk/basket", "example.co.uk"),
        ("https://a.b.example.com.au/", "example.com.au"),
        ("https://news.bbc.uk/", "bbc.uk"),
        ("https://example.com/", "example.com"),
        ("http://192.168.0.10:8080/", "192.168.0.10"),
        ("http://localhost:3000/", "localhost"),
    ])
    func siteOf(url: String, site: String) {
        #expect(SiteKey.site(of: url) == site)
    }

    @Test(arguments: ["file:///tmp/a.html", "about:blank", "chrome://extensions", "notes", "https:///path"])
    func noSiteOutsideTheWeb(url: String) {
        #expect(SiteKey.site(of: url) == nil)
    }

    private func space(_ title: String, emoji: String) -> Space {
        Space(id: UUID(), title: title, emoji: emoji, theme: SpaceTheme.presets[0], favoritesContainerID: UUID(),
              pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: Date(), profileID: nil)
    }

    /// Arc's destination menu: Most Recent Space, the spaces in order, Little Window after a separator.
    @Test func destinationMenu() {
        let work = space("Work", emoji: "💼"), plain = space("Plain", emoji: "")
        let choices = AirTrafficControl.choices(spaces: [work, plain])
        #expect(choices.map(\.title) == ["Most Recent Space", "💼 Work", "Plain", "Little Window"])
        #expect(choices.map(\.destination) == [.mostRecentSpace, .space(work.id), .space(plain.id), .littleWindow])
        #expect(choices.map(\.afterSeparator) == [false, false, false, true])
    }

    /// A route to a space that was deleted opens in the most recent space, so the menu says so.
    @Test func deletedSpaceShowsAsMostRecent() {
        let work = space("Work", emoji: "💼")
        #expect(AirTrafficControl.shown(.space(work.id), spaces: [work]) == .space(work.id))
        #expect(AirTrafficControl.shown(.space(UUID()), spaces: [work]) == .mostRecentSpace)
        #expect(AirTrafficControl.shown(.littleWindow, spaces: []) == .littleWindow)
    }

    @Test func routeSummary() {
        #expect(AirTrafficControl.summary(routes: 0) == "")
        #expect(AirTrafficControl.summary(routes: 1) == "1 route")
        #expect(AirTrafficControl.summary(routes: 3) == "3 routes")
    }
}
