import CraCore
import Foundation

/// The pinned tabs step's suggestions on Windows (ChromiumImporter.topSites and favicons on the
/// Mac): the most visited sites in a Chromium browser's History, and their icons from its
/// Favicons database into Cra's favicon cache. Read from copies (SQLiteSnapshot), so a browser
/// that's open doesn't matter.
@MainActor
enum OnboardingSites {
    static func candidates(source: WindowsImportSource?, sources: [OnboardingView.Source],
                           existingHosts: Set<String>) -> (candidates: [Onboarding.PinCandidate], ticked: Set<String>) {
        // The browser imported from, else the first one found (Dia's order).
        let entry = sources.first { $0.source == source } ?? sources.first
        let profiles = entry?.profiles ?? []
        let visited = topSites(profiles: profiles, limit: 16)
        let offered = Onboarding.pinCandidates(visited: visited, existingHosts: existingHosts)
        cacheFavicons(profiles: profiles, candidates: offered.candidates)
        return offered
    }

    static func topSites(profiles: [ChromiumProfile], limit: Int) -> [TopSite] {
        var rows: [(url: String, title: String, visits: Int)] = []
        for profile in profiles {
            guard let db = SQLiteSnapshot(copying: profile.dir.appendingPathComponent("History")) else { continue }
            for r in db.rows(TopSite.historyQuery) {
                guard let url = r["url"] as? String else { continue }
                rows.append((url: url, title: r["title"] as? String ?? "", visits: Int(r["visit_count"] as? Int64 ?? 0)))
            }
        }
        return TopSite.ranked(rows, limit: limit)
    }

    /// Each candidate's largest icon the browser has, unless Cra already has one.
    private static func cacheFavicons(profiles: [ChromiumProfile], candidates: [Onboarding.PinCandidate]) {
        var missing = candidates.compactMap { c in FaviconKey.key(for: c.url).flatMap { Favicons.shared.has($0) ? nil : (c.host, $0) } }
        for profile in profiles where !missing.isEmpty {
            guard let db = SQLiteSnapshot(copying: profile.dir.appendingPathComponent("Favicons")) else { continue }
            missing = missing.filter { host, key in
                guard let png = db.rows(TopSite.faviconQuery(host: host)).first?["image_data"] as? Data, !png.isEmpty else { return true }
                Favicons.shared.store(png: png, forKey: key)
                return !Favicons.shared.has(key)
            }
        }
    }
}
