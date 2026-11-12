import Foundation

/// The first-run onboarding, after Dia 1.54's (docs/arc-reverse-engineering.md, "Dia onboarding
/// steps"): a cover page, the default browser, privacy, the import, pinned tabs, personalization
/// and an outro. The Mac runs it in `ImportFlow.swift` with the import's own steps inside;
/// Windows runs it on one card (`OnboardingView`) around its import list. What is offered, in
/// what order, and which sites the pinned tabs step suggests are decided here.
public enum Onboarding {
    /// A fresh install: the import was never offered and the sidebar holds no more than a first
    /// window makes. Onboarding counts as seen only once it ends, so quitting halfway shows it
    /// again on the next launch.
    public static func isNeeded(hasSeenImportPrompt: Bool, tabCount: Int) -> Bool {
        !hasSeenImportPrompt && tabCount <= 2
    }

    /// The onboarding's pages. The Mac's import has its own steps inside `importData`.
    public enum Step: Int, CaseIterable, Comparable {
        case cover, defaultBrowser, privacy, importData, pinnedTabs, personalization, outro
        public static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// The steps one run shows. A step with nothing to offer is left out: the default browser
    /// step once Cra already opens links (and, on the Mac, sits in the Dock), privacy where the
    /// shell has no ad blocker or usage stats to switch on, pinned tabs once the favorites grid
    /// has a full row.
    public struct Flow: Equatable {
        public var offersDefaultBrowser: Bool
        public var offersPrivacy: Bool
        public var offersPinnedTabs: Bool

        public init(offersDefaultBrowser: Bool, offersPrivacy: Bool, offersPinnedTabs: Bool) {
            self.offersDefaultBrowser = offersDefaultBrowser
            self.offersPrivacy = offersPrivacy
            self.offersPinnedTabs = offersPinnedTabs
        }

        public var steps: [Step] {
            Step.allCases.filter { step in
                switch step {
                case .defaultBrowser: return offersDefaultBrowser
                case .privacy: return offersPrivacy
                case .pinnedTabs: return offersPinnedTabs
                default: return true
                }
            }
        }

        /// The step after `step`; nil after the outro (the onboarding ends).
        public func next(after step: Step) -> Step? { steps.first { $0 > step } }

        /// The step before `step`, for Back; nil on the cover.
        public func previous(before step: Step) -> Step? { steps.last { $0 < step } }
    }

    /// The pinned tabs step shows unless the favorites grid already has a full row.
    public static func offersPinnedTabs(favoriteCount: Int) -> Bool { favoriteCount < 4 }

    /// A site offered on the pinned tabs step (Dia's PinnedTabButton).
    public struct PinCandidate: Identifiable, Hashable, Sendable {
        public var id: String { host }
        public let host: String
        public let name: String
        public let url: String

        public init(host: String, name: String, url: String) {
            self.host = host
            self.name = name
            self.url = url
        }
    }

    /// Dia's pre-pinnable apps (PinnedTabs/Icons/* in its Onboarding bundle).
    public static let presetPins: [PinCandidate] = [
        PinCandidate(host: "mail.google.com", name: "Gmail", url: "https://mail.google.com/"),
        PinCandidate(host: "calendar.google.com", name: "Calendar", url: "https://calendar.google.com/"),
        PinCandidate(host: "app.slack.com", name: "Slack", url: "https://app.slack.com/"),
        PinCandidate(host: "notion.so", name: "Notion", url: "https://www.notion.so/"),
        PinCandidate(host: "github.com", name: "GitHub", url: "https://github.com/"),
        PinCandidate(host: "figma.com", name: "Figma", url: "https://www.figma.com/"),
        PinCandidate(host: "youtube.com", name: "YouTube", url: "https://www.youtube.com/"),
        PinCandidate(host: "open.spotify.com", name: "Spotify", url: "https://open.spotify.com/"),
        PinCandidate(host: "drive.google.com", name: "Drive", url: "https://drive.google.com/"),
        PinCandidate(host: "docs.google.com", name: "Docs", url: "https://docs.google.com/"),
        PinCandidate(host: "linear.app", name: "Linear", url: "https://linear.app/"),
        PinCandidate(host: "canva.com", name: "Canva", url: "https://www.canva.com/"),
    ]

    /// Up to six of the most visited sites from the browser imported from (Dia's
    /// rankedTopSitesTask) that aren't favorites yet, then the presets, twelve in all. The first
    /// four visited sites start ticked.
    public static func pinCandidates(visited: [TopSite], existingHosts: Set<String>) -> (candidates: [PinCandidate], ticked: Set<String>) {
        var seen = Set<String>()
        var out: [PinCandidate] = []
        for site in visited where out.count < 6 && !existingHosts.contains(site.host) && seen.insert(site.host).inserted {
            let preset = presetPins.first { $0.host == site.host }
            out.append(preset ?? PinCandidate(host: site.host, name: displayName(site), url: site.url))
        }
        let ticked = Set(out.prefix(4).map(\.host))
        for preset in presetPins where out.count < 12 && seen.insert(preset.host).inserted { out.append(preset) }
        return (out, ticked)
    }

    /// A short name for a visited site: the first part of its title when that is short, else
    /// the host's name capitalized ("news.ycombinator.com" is "Ycombinator").
    public static func displayName(_ site: TopSite) -> String {
        let title = site.title.split(whereSeparator: { "|–—-·:".contains($0) }).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !title.isEmpty && title.count <= 18 { return title }
        let base = site.host.split(separator: ".").dropLast().last.map(String.init) ?? site.host
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}

extension TopSite {
    /// What a Chromium profile's History database is asked for.
    public static let historyQuery = "SELECT url, title, visit_count FROM urls WHERE hidden = 0 ORDER BY visit_count DESC LIMIT 400"

    /// History rows from every profile as sites, one per host with the visits added up, most
    /// visited first.
    public static func ranked(_ rows: [(url: String, title: String, visits: Int)], limit: Int) -> [TopSite] {
        var visits: [String: TopSite] = [:]
        for row in rows {
            guard let site = TopSite(url: row.url, title: row.title, visits: row.visits) else { continue }
            visits[site.host, default: TopSite(host: site.host, url: site.url, title: site.title, visits: 0)].visits += site.visits
        }
        return Array(visits.values.sorted { ($0.visits, $1.host) > ($1.visits, $0.host) }.prefix(limit))
    }

    /// The largest icon a Chromium profile's Favicons database holds for `host`'s pages.
    public static func faviconQuery(host: String) -> String {
        let h = host.replacingOccurrences(of: "'", with: "")
        return """
            SELECT fb.image_data FROM favicon_bitmaps fb JOIN icon_mapping im ON fb.icon_id = im.icon_id
            WHERE im.page_url LIKE 'https://\(h)/%' OR im.page_url LIKE 'https://www.\(h)/%'
            ORDER BY fb.width DESC LIMIT 1
            """
    }
}
