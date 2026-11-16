import CraCore
import Foundation
import Testing

/// A window's slow-response notices: one clock per tab, only the front tab's shows.
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
}
