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

    /// Runs `looks` through a fresh watch: the verdicts, in order.
    private func verdicts(_ looks: [(front: Bool, enabled: Bool, hidden: Bool)]) -> [ShareRetry.OwnerWatch.Verdict] {
        var watch = ShareRetry.OwnerWatch()
        var out: [ShareRetry.OwnerWatch.Verdict] = []
        for look in looks { out.append(watch.next(ownerInFront: look.front, enabled: look.enabled, sheetHidden: look.hidden)) }
        return out
    }

    /// PR #36's PC test: a Little Window stayed disabled after its Share sheet went away when Cra
    /// came to the front; its Close and Ctrl+W did nothing until Cra quit.
    @Test func aWindowLeftDisabledBehindAGoneSheetIsEnabledAgain() {
        let sheet = (front: false, enabled: false, hidden: false)
        let stuck = (front: true, enabled: false, hidden: false)
        #expect(verdicts([sheet, stuck]) == [.wait, .wait], "the sheet may be about to show over it")
        #expect(verdicts([sheet, stuck, stuck]) == [.wait, .wait, .enable], "still so half a second later")
        #expect(verdicts([sheet, (front: true, enabled: true, hidden: false)]) == [.wait, .done], "closed as it should")
    }

    /// PR #37's PC test: a dead sheet held the front drawing nothing, and the browser window
    /// stayed disabled under it with nothing to close.
    @Test func aWindowUnderASheetThatDrawsNothingIsEnabledAgain() {
        let hidden = (front: false, enabled: false, hidden: true)
        let shown = (front: false, enabled: false, hidden: false)
        #expect(verdicts(Array(repeating: hidden, count: ShareRetry.hiddenLimit)).last == .enable)
        #expect(!verdicts(Array(repeating: hidden, count: ShareRetry.hiddenLimit - 1)).contains(.enable), "an opening animation")
        #expect(!verdicts([hidden, hidden, shown] + Array(repeating: shown, count: 20)).contains(.enable), "a sheet that draws stays")
    }

    /// PR #37's PC test: once Windows Share was wedged, it reported success and showed nothing,
    /// so the Share button seemed to do nothing at all.
    @Test func aShareThatNeverShowsSaysSo() {
        let idle = (front: true, enabled: true, hidden: false)
        #expect(verdicts(Array(repeating: idle, count: ShareRetry.shownDeadline)).last == .notShown)
        #expect(!verdicts(Array(repeating: idle, count: ShareRetry.shownDeadline - 1)).contains(.notShown))
        let elsewhere = (front: false, enabled: true, hidden: false)
        #expect(!verdicts(Array(repeating: elsewhere, count: 40)).contains(.notShown), "another app took the front: no toast")
        #expect(verdicts(Array(repeating: elsewhere, count: ShareRetry.ownerCheckLimit)).last == .done, "looking stops")
    }
}
