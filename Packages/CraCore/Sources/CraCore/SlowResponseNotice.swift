import Foundation

/// A page that accepts the connection and then takes long to answer looks blank apart from the
/// loading bar, which then had no place edge to edge or in fullscreen (GitHub #256; it has since
/// #548). After ten seconds in the loading bar's waiting phase (the request is out, nothing
/// committed), Cra says so in its toast with Stop Loading; the request goes on unless that is pressed.
///
/// Not Arc: Arc 1.172.1 shows nothing more than the bar during a long wait (offline copy against
/// a local server that answers after 40 s, 8 Nov 2026: white page, "Untitled" tab, the address
/// reading about:blank, no status text, identical frames at 13, 20 and 30 s). The notice is Arc's
/// own toast (ShinyToast) with its button and ✕, like Cra's other notices.
///
/// One per tab. It goes as soon as the page answers (commits; a slow image after that never brings
/// it back), fails (Cra's error page commits too), is stopped, or its ✕ is pressed; ✕ holds for
/// that navigation only.
public struct SlowResponseNotice: Equatable, Sendable {
    /// How long a navigation waits for its first response before the notice shows.
    public static let delay: TimeInterval = 10

    /// When the current navigation started waiting; nil while the tab isn't waiting.
    public private(set) var waitingSince: Date?
    private var navigation = 0
    private var closed = false

    public init() {}

    /// The tab's loading phase as of `now`. `navigation` counts the main-frame navigations the
    /// page started (not redirects): another one while still waiting starts the clock again.
    public mutating func update(_ phase: LoadingIndicator.Phase, navigation: Int, now: Date) {
        guard phase == .waiting else {
            waitingSince = nil
            closed = false
            return
        }
        if waitingSince == nil || navigation != self.navigation {
            waitingSince = now
            closed = false
        }
        self.navigation = navigation
    }

    public func isShown(at now: Date) -> Bool {
        guard let waitingSince, !closed else { return false }
        return now.timeIntervalSince(waitingSince) >= Self.delay
    }

    /// When it shows if nothing changes before then; nil when it won't on its own.
    public var showsAt: Date? {
        closed ? nil : waitingSince?.addingTimeInterval(Self.delay)
    }

    /// The ✕: gone until the next navigation waits.
    public mutating func close() {
        if waitingSince != nil { closed = true }
    }

    /// The toast's text for the address being loaded: its host, without "www.".
    public static func message(for url: String) -> String {
        let host = URL(string: url)?.host.map(Boost.siteHost) ?? ""
        return "Still waiting for \(host.isEmpty ? "the page" : host) to respond"
    }
}

/// Every tab's SlowResponseNotice in a window. Each tab keeps its own clock; only a page on
/// screen can show a notice. In a split, a waiting pane still needs its notice while another
/// pane has the focus (BrowserWindow on Windows).
public struct SlowResponseNotices: Equatable, Sendable {
    /// A live page's loading phase and the main-frame navigations it has started.
    public struct Page: Equatable, Sendable {
        public var phase: LoadingIndicator.Phase
        public var navigation: Int

        public init(phase: LoadingIndicator.Phase, navigation: Int) {
            self.phase = phase
            self.navigation = navigation
        }
    }

    /// What the window does after an update.
    public struct State: Equatable, Sendable {
        /// The tab whose notice is up, nil when none is.
        public var shown: UUID?
        /// When to update again, for a visible page's notice to fall due; nil when nothing will
        /// change on its own.
        public var checkAt: Date?

        public init(shown: UUID?, checkAt: Date?) {
            self.shown = shown
            self.checkAt = checkAt
        }
    }

    public private(set) var notices: [UUID: SlowResponseNotice] = [:]

    public init() {}

    /// `pages`: every live page, by tab (a page that went takes its notice with it); `front`:
    /// the only tab on screen. Split-aware callers pass every visible pane instead.
    public mutating func update(_ pages: [UUID: Page], front: UUID?, now: Date) -> State {
        update(pages, visible: front.map { [$0] } ?? [], focused: front, now: now)
    }

    /// A notice from any visible pane may show. Prefer the focused pane once its own wait is
    /// due; before then it must not hide another pane's due notice. Other panes follow their
    /// display order. Hidden pages keep their clocks but never cause a wake-up on their own.
    public mutating func update(_ pages: [UUID: Page], visible: [UUID], focused: UUID?, now: Date) -> State {
        var next: [UUID: SlowResponseNotice] = [:]
        for (id, page) in pages {
            var n = notices[id] ?? SlowResponseNotice()
            n.update(page.phase, navigation: page.navigation, now: now)
            next[id] = n
        }
        notices = next
        var seen = Set<UUID>()
        var onScreen = visible.filter { seen.insert($0).inserted }
        if let focused, let index = onScreen.firstIndex(of: focused) {
            onScreen.remove(at: index)
            onScreen.insert(focused, at: 0)
        }
        let shown = onScreen.first { next[$0]?.isShown(at: now) == true }
        let due = onScreen.compactMap { next[$0]?.showsAt }.filter { $0 > now }.min()
        return State(shown: shown, checkAt: due)
    }

    /// The ✕ on `id`'s notice: gone until that tab's next navigation waits.
    public mutating func close(_ id: UUID) {
        notices[id]?.close()
    }
}
