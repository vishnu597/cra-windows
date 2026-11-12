import CraCore
import Testing

struct OnboardingTests {
    @Test func onlyAFreshInstallRunsIt() {
        #expect(Onboarding.isNeeded(hasSeenImportPrompt: false, tabCount: 0))
        #expect(Onboarding.isNeeded(hasSeenImportPrompt: false, tabCount: 2))
        #expect(!Onboarding.isNeeded(hasSeenImportPrompt: false, tabCount: 3), "someone has been browsing")
        #expect(!Onboarding.isNeeded(hasSeenImportPrompt: true, tabCount: 0), "ended once already")
    }

    @Test func everyStepInDiasOrder() {
        let flow = Onboarding.Flow(offersDefaultBrowser: true, offersPrivacy: true, offersPinnedTabs: true)
        #expect(flow.steps == Onboarding.Step.allCases)
        #expect(flow.next(after: .cover) == .defaultBrowser)
        #expect(flow.next(after: .outro) == nil)
        #expect(flow.previous(before: .cover) == nil)
        #expect(flow.previous(before: .importData) == .privacy)
    }

    @Test func stepsWithNothingToOfferAreLeftOut() {
        // Windows: Cra already opens links, no ad blocker or usage stats yet, four favorites.
        let flow = Onboarding.Flow(offersDefaultBrowser: false, offersPrivacy: false, offersPinnedTabs: false)
        #expect(flow.steps == [.cover, .importData, .personalization, .outro])
        #expect(flow.next(after: .cover) == .importData)
        #expect(flow.next(after: .importData) == .personalization)
        #expect(flow.previous(before: .personalization) == .importData)
    }

    @Test func pinnedTabsWaitForAFullRow() {
        #expect(Onboarding.offersPinnedTabs(favoriteCount: 3))
        #expect(!Onboarding.offersPinnedTabs(favoriteCount: 4))
    }

    @Test func visitedSitesComeFirstAndTheFirstFourAreTicked() {
        let visited = ["news.ycombinator.com", "github.com", "example.com", "wikipedia.org", "reddit.com", "x.com", "bbc.co.uk"]
            .map { TopSite(host: $0, url: "https://\($0)/", title: "", visits: 1) }
        let (candidates, ticked) = Onboarding.pinCandidates(visited: visited, existingHosts: ["example.com"])
        #expect(candidates.count == 12)
        #expect(candidates.prefix(6).map(\.host) == ["news.ycombinator.com", "github.com", "wikipedia.org", "reddit.com", "x.com", "bbc.co.uk"],
                "six visited sites, leaving out a favorite")
        #expect(candidates[1].name == "GitHub", "a visited preset keeps its own name")
        #expect(candidates[0].name == "Ycombinator")
        #expect(ticked == ["news.ycombinator.com", "github.com", "wikipedia.org", "reddit.com"])
        #expect(candidates.filter { $0.host == "github.com" }.count == 1, "a preset isn't offered twice")
    }

    @Test func withNoHistoryThePresetsAreOfferedUnticked() {
        let (candidates, ticked) = Onboarding.pinCandidates(visited: [], existingHosts: [])
        #expect(candidates == Onboarding.presetPins)
        #expect(ticked.isEmpty)
    }

    @Test func aShortTitleNamesTheSite() {
        #expect(Onboarding.displayName(TopSite(host: "lobste.rs", url: "https://lobste.rs/", title: "Lobsters | Computing", visits: 1)) == "Lobsters")
        #expect(Onboarding.displayName(TopSite(host: "nytimes.com", url: "https://nytimes.com/", title: "The New York Times - Breaking News, US News", visits: 1)) == "The New York Times")
        #expect(Onboarding.displayName(TopSite(host: "nytimes.com", url: "https://nytimes.com/", title: "", visits: 1)) == "Nytimes")
    }

    @Test func historyRowsAddUpPerHost() {
        let rows: [(url: String, title: String, visits: Int)] = [
            (url: "https://github.com/a", title: "A", visits: 5),
            (url: "https://www.github.com/b", title: "B", visits: 7),
            (url: "https://example.com/", title: "Example", visits: 9),
            (url: "https://www.google.com/search?q=x", title: "x", visits: 50),
            (url: "chrome://settings", title: "Settings", visits: 40),
        ]
        let sites = TopSite.ranked(rows, limit: 5)
        #expect(sites.map(\.host) == ["github.com", "example.com"])
        #expect(sites.map(\.visits) == [12, 9])
        #expect(TopSite.ranked(rows, limit: 1).count == 1)
    }

    @Test func theFaviconQueryCannotBeBrokenOutOf() {
        #expect(!TopSite.faviconQuery(host: "a.com' OR 1=1 --").contains("a.com'"))
        #expect(TopSite.faviconQuery(host: "github.com").contains("'https://www.github.com/%'"))
    }
}
