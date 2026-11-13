import Foundation

// Arc's Air Traffic Control (Settings ▸ Links ▸ Air Traffic Control…, stored in
// StorableLinkRouting.json, see docs/arc-reverse-engineering.md): a link from another
// app is checked against the routes in order, the first match decides where it opens
// and anything else goes to the default destination.

/// Arc's LinkSourceTextMatchingStyle (`matches` / `contains`).
public enum LinkMatchStyle: String, Codable, CaseIterable, Identifiable {
    case equals, contains
    public var id: String { rawValue }
    public var label: String { self == .equals ? "Is equal to" : "Contains" }
}

/// Arc's LinkDestination is `space(ProfileDestination)` or `littleArc(ProfileDestination)`
/// with ProfileDestination `mostRecent | space(id) | profile(…)`. Its editor only offers
/// space(mostRecent), space(id) and littleArc(mostRecent); a hand-written littleArc(space)
/// only picked the page's profile and still said "Open in <most recent space>".
/// A space destination opens a new foreground tab in that space's Today list (also when
/// the URL is already open) and switches the window to the space.
/// A Little Window may name a space (#258, past Arc): the page loads in that space's
/// profile and "Open in" / ⌘O sends it there; nil is the space in use, as in Arc.
public enum LinkDestination: Codable, Hashable {
    case mostRecentSpace
    case space(UUID)
    /// Saved as `{"littleWindow": {}}` without a space, as before #258, and
    /// `{"littleWindow": {"space": "<id>"}}` with one, which older Cra reads as a plain
    /// Little Window rather than dropping the routes.
    case littleWindow(space: UUID?)

    /// A Little Window in the space in use.
    public static let littleWindowInUse = LinkDestination.littleWindow(space: nil)

    public var isLittleWindow: Bool {
        if case .littleWindow = self { return true }
        return false
    }
}

public struct LinkRoute: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var match: LinkMatchStyle = .contains
    public var text = ""
    public var destination: LinkDestination = .mostRecentSpace

    public init(id: UUID = UUID(), match: LinkMatchStyle = .contains, text: String = "", destination: LinkDestination = .mostRecentSpace) {
        self.id = id
        self.match = match
        self.text = text
        self.destination = destination
    }

    /// Matches like Arc 1.170 (observed by handing it links, see docs/arc-reverse-engineering.md):
    /// both sides lose case, the scheme and a leading `www.`; "Contains" then searches the
    /// rest including query and fragment, while "Is equal to" also drops the query, the
    /// fragment and trailing slashes, so `example.com/a` equals `http://www.example.com/a/?x#y`
    /// but not `example.com/a/b`. An empty route matches nothing.
    public func matches(_ url: String) -> Bool {
        let want = Self.normalized(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !want.isEmpty else { return false }
        let have = Self.normalized(url)
        switch match {
        case .contains: return have.contains(want)
        case .equals: return Self.page(have) == Self.page(want)
        }
    }

    private static func normalized(_ url: String) -> String {
        var s = Substring(url.lowercased())
        if let r = s.range(of: "://") { s = s[r.upperBound...] }
        if s.hasPrefix("www.") { s = s.dropFirst(4) }
        return String(s)
    }

    /// Host and path only.
    private static func page(_ s: String) -> Substring {
        var p = s[..<(s.firstIndex { $0 == "?" || $0 == "#" } ?? s.endIndex)]
        while p.hasSuffix("/") { p = p.dropLast() }
        return p
    }

    /// Arc seeds this route once (AppState+DefaultLinkRoutes, `didSetDefaultGoogleMeetRoute`)
    /// so calls open in a full window rather than in Little Arc.
    public static let googleMeet = LinkRoute(match: .contains, text: "meet.google.com", destination: .mostRecentSpace)
}

extension AppSettings {
    /// Where a link from another app opens: the first matching route, else the default.
    public func destination(forExternalURL url: String) -> LinkDestination {
        linkRoutes.first { $0.matches(url) }?.destination ?? defaultLinkDestination
    }

    /// The space a URL typed in the ⌘T bar opens in (#421): Arc 1.173 runs it through the routes
    /// too, and when the first match is a route to a space the new tab opens there and the window
    /// switches to it. Nil keeps it in the space in use: no match (the default never applies, a
    /// typed URL that matches nothing stays put in Arc), Most Recent Space (the window's own) and
    /// a Little Window (not seen in Arc for typed URLs).
    public func space(forTypedURL url: String) -> UUID? {
        guard case .space(let id)? = linkRoutes.first(where: { $0.matches(url) })?.destination else { return nil }
        return id
    }
}

/// Arc's Peek opens links "to other sites": the registrable domain differs, so a link from
/// mail.google.com to accounts.google.com stays in the tab. Cra has no public suffix list;
/// a generic second-level label under a country code (co.uk, com.au) counts as suffix.
public enum SiteKey {
    private static let secondLevel: Set<Substring> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go", "gv"]

    public static func site(of url: String) -> String? {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host?.lowercased(), !host.isEmpty else { return nil }
        let labels = host.split(separator: ".")
        if labels.count <= 2 || host.allSatisfy({ $0.isNumber || $0 == "." }) || host.contains(":") { return host }
        let n = labels.count
        let keep = labels[n - 1].count == 2 && secondLevel.contains(labels[n - 2]) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}

/// Arc's Air Traffic Control sheet (Settings ▸ Tabs ▸ Links ▸ "Air Traffic Control…"): its words
/// and its destination menu, which the Mac's AirTrafficControlView and Windows' sheet both show.
public enum AirTrafficControl {
    public static let title = "Air Traffic Control"
    public static let openInSpaceTitle = "Open in Space"
    public static let littleWindowInTitle = "Little Window in"
    public static let emptyNote = "Add a route to open matching links from other apps in a chosen space."
    public static let placeholder = "crabrowser.app"
    public static let settingsNote = "Choose which space links from other apps open in."

    /// Next to the Settings button: nothing, "1 route", "3 routes".
    public static func summary(routes: Int) -> String {
        switch routes {
        case ...0: return ""
        case 1: return "1 route"
        default: return "\(routes) routes"
        }
    }

    /// The description under the Links pane's Air Traffic Control row.
    public static func routesDetail(routes: Int) -> String {
        let lead = "Send links from other apps to the space you choose, by what their address contains."
        guard routes > 0 else { return lead }
        return lead + " \(routes) \(routes == 1 ? "route" : "routes") set."
    }

    /// One entry of the destination menu.
    public struct Choice: Equatable {
        public let destination: LinkDestination
        public let title: String
        /// The first entry after Arc's separator (Little Window).
        public let afterSeparator: Bool
    }

    /// Arc's menu: Most Recent Space and every space (under "Open in Space"), then Little Window
    /// after a separator.
    public static func choices(spaces: [Space]) -> [Choice] {
        [Choice(destination: .mostRecentSpace, title: "Most Recent Space", afterSeparator: false)]
            + spaces.map { Choice(destination: .space($0.id), title: $0.emoji.isEmpty ? $0.title : "\($0.emoji) \($0.title)", afterSeparator: false) }
            + [Choice(destination: .littleWindowInUse, title: "Little Window", afterSeparator: true)]
    }

    /// The secondary space menu for a Little Window: the space in use or a named space.
    public static func littleWindowChoices(spaces: [Space]) -> [Choice] {
        choices(spaces: spaces).compactMap { choice in
            switch choice.destination {
            case .mostRecentSpace:
                return Choice(destination: .littleWindowInUse, title: choice.title, afterSeparator: false)
            case .space(let id):
                return Choice(destination: .littleWindow(space: id), title: choice.title, afterSeparator: false)
            case .littleWindow:
                return nil
            }
        }
    }

    /// The named space a Little Window uses, nil for the space in use or one deleted since.
    public static func littleWindowSpace(_ destination: LinkDestination, spaces: [Space]) -> UUID? {
        guard case .littleWindow(let id) = destination else { return nil }
        return id.flatMap { id in spaces.contains(where: { $0.id == id }) ? id : nil }
    }

    /// Re-selecting the primary Little Window entry keeps its secondary space selection.
    public static func selecting(_ destination: LinkDestination, current: LinkDestination) -> LinkDestination {
        destination.isLittleWindow && current.isLittleWindow ? current : destination
    }

    /// What the menu shows for `destination`: a route to a deleted space opens in the most recent
    /// one, so it shows that way.
    public static func shown(_ destination: LinkDestination, spaces: [Space]) -> LinkDestination {
        if destination.isLittleWindow { return .littleWindowInUse }
        if case .space(let id) = destination, !spaces.contains(where: { $0.id == id }) { return .mostRecentSpace }
        return destination
    }
}
