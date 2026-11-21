import Foundation

/// One added list's line in Settings ▸ Privacy ▸ Block lists (#507), as both apps show it: its
/// name, then what it blocks and when it was fetched, why it couldn't be, or that it's on its way.
public enum BlocklistRow {
    /// The row's explanation under "Block lists".
    public static let detail = "Add a list to block more, like ads in your country. Cra uses its domain rules (hosts files, domain lists and Adblock Plus “||domain^” rules) and fetches it again when Cra opens, once a day at most."

    /// What Add with a bad address says.
    public static let invalidAddress = "Enter the list’s web address, like https://example.com/list.txt."

    /// The list's own title once fetched, else its file name or host.
    public static func name(_ address: String, cached: CachedBlocklist?) -> String {
        if let cached { return cached.name }
        guard let url = URL(string: address) else { return address }
        return url.isFileURL ? url.lastPathComponent : (url.host ?? address)
    }

    public enum Status: Equatable {
        case fetching
        case failed(String)
        case fetched(String)
    }

    /// A failure wins over the copy Cra keeps, as on the Mac.
    public static func status(cached: CachedBlocklist?, failure: String?, now: Date) -> Status {
        if let failure { return .failed(failure) }
        guard let cached else { return .fetching }
        return .fetched(CustomBlocklist.summary(domains: cached.domains.count, skippedRules: cached.skippedRules)
                        + " · Updated " + updated(cached.fetched, now: now))
    }

    /// When a list was fetched, said the way the Mac's relative date says it in English.
    public static func updated(_ fetched: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(fetched)
        if seconds < 60 { return "now" }
        let minutes = Int(seconds / 60), hours = Int(seconds / 3600), days = Int(seconds / 86400)
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        let weeks = days / 7
        return weeks == 1 ? "last week" : "\(weeks) weeks ago"
    }
}
