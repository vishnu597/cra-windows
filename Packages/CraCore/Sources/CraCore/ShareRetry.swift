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
}
