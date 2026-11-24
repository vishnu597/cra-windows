/// The line of permission requests waiting for one window's card (#286, #371), with
/// `PermissionAsk`'s rules: a request asks only while its tab is on screen, one card at a time,
/// and a card whose tab goes behind steps aside and waits first in line until its tab is back,
/// as Chrome's bubble does. The Mac keeps the same line in BrowserManager; Windows'
/// BrowserWindow keeps it here.
public struct PermissionLine<Request> {
    /// The request whose card is up.
    public private(set) var asking: Request?
    /// The requests waiting, oldest first.
    public private(set) var waiting: [Request] = []

    public init() {}

    public var isEmpty: Bool { asking == nil && waiting.isEmpty }
    public var all: [Request] { (asking.map { [$0] } ?? []) + waiting }

    /// A request arrives. True when it asks now; otherwise it waits behind the others.
    public mutating func add(_ request: Request, tabShown: Bool) -> Bool {
        if PermissionAsk.waits(tabShown: tabShown, sheetUp: asking != nil) {
            waiting.append(request)
            return false
        }
        asking = request
        return true
    }

    /// The card was answered (or dropped): the request it asked for leaves the line.
    @discardableResult public mutating func finish() -> Request? {
        defer { asking = nil }
        return asking
    }

    /// The tabs on screen changed. The card whose tab went behind steps aside (returned in
    /// `aside`, first in line again), and once no card is up the oldest waiting request whose tab
    /// is on screen asks (`next`).
    public mutating func tabsChanged(shown: (Request) -> Bool) -> (aside: Request?, next: Request?) {
        var aside: Request?
        if let up = asking, PermissionAsk.stepsAside(tabShown: shown(up)) {
            asking = nil
            waiting.insert(up, at: 0)
            aside = up
        }
        guard asking == nil, let i = waiting.firstIndex(where: shown) else { return (aside, nil) }
        let next = waiting.remove(at: i)
        asking = next
        return (aside, next)
    }

    /// Requests that will never be answered here (their page closed or withdrew them) leave the
    /// line, the asking one first when it is among them. `wasAsking` says its card must go.
    public mutating func remove(where matches: (Request) -> Bool) -> (removed: [Request], wasAsking: Bool) {
        var removed = waiting.filter(matches)
        waiting.removeAll(where: matches)
        var wasAsking = false
        if let up = asking, matches(up) {
            asking = nil
            removed.insert(up, at: 0)
            wasAsking = true
        }
        return (removed, wasAsking)
    }
}
