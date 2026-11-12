/// Windows Share can report that its out-of-process server is temporarily busy. Retry only
/// that result, briefly, so a failed Share action always ends with visible feedback.
public enum ShareRetry {
    public enum Result { case opened, busy, failed }
    public enum Action: Equatable { case opened, retry(after: Double), failed }

    public static let failureMessage = "Couldn't open Windows Share. Try again in a moment."

    /// `attempt` includes the initial call: six calls, with five 200 ms waits, at most.
    public static func action(after result: Result, attempt: Int) -> Action {
        switch result {
        case .opened: return .opened
        case .failed: return .failed
        case .busy: return (1..<6).contains(attempt) ? .retry(after: 0.2) : .failed
        }
    }

    /// Windows' Share sheet disables the window it opens over and enables it again when it closes.
    /// It can go wrong three ways (PR #36's and #37's PC tests): it lost the front to Cra and left
    /// the window disabled; it held the front drawing nothing (cloaked) with the window disabled
    /// under it; or it reported success and never showed. After a Share
    /// opens, Cra looks every `ownerCheckInterval` seconds, for `ownerCheckLimit` looks.
    public static let ownerCheckInterval = 0.5
    public static let ownerCheckLimit = 1_200
    /// Looks before a Share that never disabled its window, with Cra still in front, counts as
    /// not shown: 4 seconds.
    public static let shownDeadline = 8
    /// Looks a sheet in front may draw nothing (cloaked) before its window is enabled again:
    /// 3 seconds, well past any opening animation.
    public static let hiddenLimit = 6

    public struct OwnerWatch: Equatable {
        public enum Verdict: Equatable {
            /// The sheet is up, or may still come: look again.
            case wait
            /// The sheet closed as it should, or looking took long enough: stop.
            case done
            /// The window is in front yet disabled two looks running, or under a sheet that
            /// draws nothing: enable it and stop. A real sheet would have enabled it itself.
            case enable
            /// Nothing showed: say Share failed and stop.
            case notShown
        }

        public private(set) var look = 0
        private var sheetSeen = false
        private var suspected = false
        private var hiddenLooks = 0

        public init() {}

        /// One look. `ownerInFront`: the window is the foreground window; `enabled`: it takes
        /// input; `sheetHidden`: the foreground window draws nothing (DWM cloaks it).
        public mutating func next(ownerInFront: Bool, enabled: Bool, sheetHidden: Bool) -> Verdict {
            look += 1
            if !enabled { sheetSeen = true }
            if ownerInFront {
                hiddenLooks = 0
                if !enabled {
                    if suspected { return .enable }
                    suspected = true
                    return .wait
                }
                suspected = false
                if sheetSeen { return .done }
                if look >= ShareRetry.shownDeadline { return .notShown }
            } else {
                suspected = false
                hiddenLooks = !enabled && sheetHidden ? hiddenLooks + 1 : 0
                if hiddenLooks >= ShareRetry.hiddenLimit { return .enable }
            }
            return look >= ShareRetry.ownerCheckLimit ? .done : .wait
        }
    }
}
