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
    /// When the sheet goes another way (it lost the front to Cra itself, PR #36's PC test) the
    /// window stays disabled: its buttons and keys do nothing until Cra quits. After a Share
    /// opens, Cra looks every `ownerCheckInterval` seconds, for `ownerCheckLimit` looks: a window
    /// that is in front yet disabled has no sheet over it any more, so it is enabled again.
    public static let ownerCheckInterval = 0.5
    public static let ownerCheckLimit = 1_200

    public enum OwnerCheck: Equatable {
        /// The sheet is still up (or the window is fine but may still get one): look again.
        case wait
        /// In front and disabled once: the sheet may be just about to show. Look again.
        case suspect
        /// The window is back and works: stop looking.
        case done
        /// In front and disabled two looks running: enable it, then stop.
        case enable
    }

    /// What one look finds. `ownerInFront`: the window is the foreground window; `enabled`: it
    /// takes input; `sheetSeen`: it has been disabled (the sheet was up) since Share opened;
    /// `suspected`: the last look said `.suspect`.
    public static func ownerCheck(ownerInFront: Bool, enabled: Bool, sheetSeen: Bool, suspected: Bool, look: Int) -> OwnerCheck {
        if ownerInFront && !enabled { return suspected ? .enable : .suspect }
        if ownerInFront && enabled && sheetSeen { return .done }
        return look >= ownerCheckLimit ? .done : .wait
    }
}
