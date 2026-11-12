import CraCore
import Testing

struct ShareRetryTests {
    @Test func successAndPermanentFailuresNeverRetry() {
        for attempt in 1...6 {
            #expect(ShareRetry.action(after: .opened, attempt: attempt) == .opened)
            #expect(ShareRetry.action(after: .failed, attempt: attempt) == .failed)
        }
    }

    @Test func aTemporarilyBusyShareCanOpenWithoutWaitingForTheLimit() {
        let results: [ShareRetry.Result] = [.busy, .busy, .opened]
        let actions = results.enumerated().map { ShareRetry.action(after: $0.element, attempt: $0.offset + 1) }
        #expect(actions == [.retry(after: 0.2), .retry(after: 0.2), .opened])
    }

    @Test func persistentBusyStopsAfterSixTotalAttemptsAndOneSecond() {
        var retries = 0
        var totalDelay = 0.0
        for attempt in 1...6 {
            switch ShareRetry.action(after: .busy, attempt: attempt) {
            case .retry(let delay):
                #expect(delay >= 0.1, "COM must get at least 100 ms before another attempt")
                retries += 1
                totalDelay += delay
            case .failed:
                #expect(attempt == 6, "six includes the initial attempt")
            case .opened:
                Issue.record("A busy result cannot report that Share opened")
            }
        }
        #expect(retries == 5)
        #expect(totalDelay == 1)
        #expect(ShareRetry.action(after: .busy, attempt: 7) == .failed)
        #expect(ShareRetry.action(after: .busy, attempt: 0) == .failed)
    }

    /// PR #36's PC test: a Little Window stayed disabled after its Share sheet went away when Cra
    /// came to the front; its Close and Ctrl+W did nothing until Cra quit.
    @Test func aWindowLeftDisabledBehindAGoneSheetIsEnabledAgain() {
        func check(front: Bool, enabled: Bool, seen: Bool = true, suspected: Bool = false, look: Int = 3) -> ShareRetry.OwnerCheck {
            ShareRetry.ownerCheck(ownerInFront: front, enabled: enabled, sheetSeen: seen, suspected: suspected, look: look)
        }
        #expect(check(front: true, enabled: false) == .suspect, "the sheet may be about to show over it")
        #expect(check(front: true, enabled: false, suspected: true) == .enable, "still so half a second later: stuck")
        #expect(check(front: false, enabled: false) == .wait, "the sheet is in front")
        #expect(check(front: true, enabled: true) == .done, "the sheet closed as it should")
        #expect(check(front: true, enabled: true, seen: false, look: 1) == .wait, "the sheet may not be up yet")
        #expect(check(front: false, enabled: true, seen: false, look: ShareRetry.ownerCheckLimit) == .done, "looking stops")
    }
}
