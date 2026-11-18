import CraCore
import Foundation
import Testing

/// A window's slow-response notices: one clock per tab, including unfocused visible split panes.
struct SlowResponseNoticesTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    let a = UUID(), b = UUID()
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    func waiting(_ navigation: Int = 1) -> SlowResponseNotices.Page { .init(phase: .waiting, navigation: navigation) }

    @Test func theFrontTabShowsOnceItsTimeIsUp() {
        var n = SlowResponseNotices()
        var state = n.update([a: waiting()], front: a, now: t0)
        #expect(state.shown == nil)
        #expect(state.checkAt == at(10))
        state = n.update([a: waiting()], front: a, now: at(10))
        #expect(state.shown == a)
        #expect(state.checkAt == nil)
    }

    @Test func aTabBehindKeepsItsClockAndShowsWhenItComesToTheFront() {
        var n = SlowResponseNotices()
        _ = n.update([a: waiting(), b: .init(phase: .loading, navigation: 1)], front: b, now: t0)
        var state = n.update([a: waiting(), b: .init(phase: .loading, navigation: 1)], front: b, now: at(12))
        #expect(state.shown == nil)
        #expect(state.checkAt == nil)
        state = n.update([a: waiting(), b: .init(phase: .loading, navigation: 1)], front: a, now: at(13))
        #expect(state.shown == a)
        // Away again: down, though a goes on waiting.
        state = n.update([a: waiting(), b: .init(phase: .loading, navigation: 1)], front: b, now: at(14))
        #expect(state.shown == nil)
    }

    @Test func closingHoldsForThatNavigationOnly() {
        var n = SlowResponseNotices()
        _ = n.update([a: waiting()], front: a, now: t0)
        #expect(n.update([a: waiting()], front: a, now: at(10)).shown == a)
        n.close(a)
        var state = n.update([a: waiting()], front: a, now: at(20))
        #expect(state.shown == nil)
        #expect(state.checkAt == nil)
        // The next navigation waits again: its own ten seconds.
        state = n.update([a: waiting(2)], front: a, now: at(21))
        #expect(state.shown == nil)
        #expect(state.checkAt == at(31))
    }

    @Test func aClosedPageTakesItsNoticeWithIt() {
        var n = SlowResponseNotices()
        _ = n.update([a: waiting(), b: waiting()], front: a, now: t0)
        _ = n.update([b: waiting()], front: b, now: at(1))
        #expect(n.notices[a] == nil)
        // A page made again under the same tab starts from nothing.
        let state = n.update([a: waiting(), b: waiting()], front: a, now: at(5))
        #expect(state.checkAt == at(15))
    }

    @Test func noFrontTabShowsNothing() {
        var n = SlowResponseNotices()
        _ = n.update([a: waiting()], front: nil, now: t0)
        let state = n.update([a: waiting()], front: nil, now: at(30))
        #expect(state == .init(shown: nil, checkAt: nil))
    }

    @Test func aVisibleSplitPaneShowsWhileTheFocusedPaneHasAnswered() {
        var n = SlowResponseNotices()
        let pages = [a: waiting(), b: Page(phase: .loading, navigation: 1)]
        let start = n.update(pages, visible: [a, b], focused: b, now: t0)
        #expect(start == .init(shown: nil, checkAt: at(10)))
        let due = n.update(pages, visible: [a, b], focused: b, now: at(10))
        #expect(due == .init(shown: a, checkAt: nil))
    }

    @Test func aNewWaitInTheFocusedPaneDoesNotHideAnotherPanesDueNotice() {
        var n = SlowResponseNotices()
        _ = n.update([a: waiting()], visible: [a, b], focused: b, now: t0)
        let state = n.update([a: waiting(), b: waiting()], visible: [a, b], focused: b, now: at(12))
        #expect(state == .init(shown: a, checkAt: at(22)))
        let focusedDue = n.update([a: waiting(), b: waiting()], visible: [a, b], focused: b, now: at(22))
        #expect(focusedDue == .init(shown: b, checkAt: nil), "the focused pane wins once its own wait is due")
    }

    @Test func closingOnePanesNoticeLeavesTheOtherPanesWaitAlone() {
        var n = SlowResponseNotices()
        let pages = [a: waiting(), b: waiting()]
        _ = n.update(pages, visible: [a, b], focused: b, now: t0)
        #expect(n.update(pages, visible: [a, b], focused: b, now: at(10)).shown == b)
        n.close(b)
        #expect(n.update(pages, visible: [a, b], focused: b, now: at(11)).shown == a)
        n.close(a)
        #expect(n.update(pages, visible: [a, b], focused: b, now: at(12)) == .init(shown: nil, checkAt: nil))
        let nextNavigation = n.update([a: waiting(), b: waiting(2)], visible: [a, b], focused: b, now: at(13))
        #expect(nextNavigation == .init(shown: nil, checkAt: at(23)))
    }

    @Test func hiddenPagesNeverShowOrScheduleANotice() {
        var n = SlowResponseNotices()
        _ = n.update([a: waiting()], visible: [], focused: a, now: t0)
        let hidden = n.update([a: waiting()], visible: [b], focused: a, now: at(15))
        #expect(hidden == .init(shown: nil, checkAt: nil), "a stale focused id does not make a hidden page visible")
        #expect(n.update([a: waiting()], visible: [a], focused: nil, now: at(16)).shown == a)
    }

    @Test func theNextCheckIsTheEarliestVisiblePanesDeadline() {
        var n = SlowResponseNotices()
        let hidden = UUID()
        _ = n.update([hidden: waiting()], visible: [], focused: nil, now: t0)
        _ = n.update([hidden: waiting(), a: waiting()], visible: [a, b], focused: b, now: at(2))
        let state = n.update([hidden: waiting(), a: waiting(), b: waiting()], visible: [b, a], focused: b, now: at(5))
        #expect(state == .init(shown: nil, checkAt: at(12)))
        let firstDue = n.update([hidden: waiting(), a: waiting(), b: waiting()], visible: [b, a], focused: b, now: at(12))
        #expect(firstDue == .init(shown: a, checkAt: at(15)))
    }

    private typealias Page = SlowResponseNotices.Page
}
