import CraCore
import Foundation
import Testing

/// Arc's "+" past the last space from a touchpad's sideways wheel on Windows: the travel fills
/// the ring on the Mac's rubber band, a pause is the lift, and a ring held full makes a space.
struct NewSpaceWheelPullTests {
    private let width: CGFloat = 260

    /// Wheel events `lines` apart every 10 ms from `start`, toward the next space.
    private func pulled(_ events: Int, lines: CGFloat = -0.5, start: TimeInterval = 1) -> NewSpaceWheelPull {
        var p = NewSpaceWheelPull()
        for i in 0..<events { p.pull(lines: lines, width: width, at: start + Double(i) * 0.01) }
        return p
    }

    @Test
    func travelFollowsTheWheelOnTheMacsBand() {
        var p = NewSpaceWheelPull()
        let o = p.pull(lines: -1, width: width, at: 1)
        #expect(p.travel == NewSpaceWheelPull.pointsPerLine)
        #expect(o == NewSpaceSwipe.overscroll(travel: NewSpaceWheelPull.pointsPerLine, page: width))
        #expect(o > 0 && o < NewSpaceWheelPull.pointsPerLine)
    }

    @Test
    func wheelingBackTakesTravelOffAndNeverBelowNothing() {
        var p = pulled(4)
        p.pull(lines: 2, width: width, at: 1.04)
        #expect(p.travel == 0)
        p.pull(lines: 3, width: width, at: 1.05)
        #expect(p.travel == 0)
    }

    @Test
    func aRingHeldFullMakesASpaceOnLift() {
        // 40 events of half a line: 800 pt of travel, full well before the last 0.1 s.
        var p = pulled(40)
        #expect(NewSpaceSwipe.isActivated(overscroll: p.overscroll(width: width)))
        #expect(!p.isLifted(at: 1.40))
        #expect(p.isLifted(at: 1.39 + NewSpaceWheelPull.liftPause + 0.01))
        let lifted = p.lift()
        #expect(lifted)
        #expect(p.travel == 0 && p.fullSince == nil)
    }

    @Test
    func aRingFullTooBrieflyOrNotFullMakesNothing() {
        var short = pulled(3)
        #expect(!NewSpaceSwipe.isActivated(overscroll: short.overscroll(width: width)))
        let shortLifted = short.lift()
        #expect(!shortLifted)
        // Full on the last event only.
        var p = NewSpaceWheelPull()
        var t: TimeInterval = 1
        while !NewSpaceSwipe.isActivated(overscroll: p.pull(lines: -0.5, width: width, at: t)) { t += 0.01 }
        #expect(p.fullSince == t)
        let lifted = p.lift()
        #expect(!lifted)
    }

    @Test
    func pullingBackUnderFullForgetsTheHold() {
        var p = pulled(40)
        #expect(p.fullSince != nil)
        p.pull(lines: 20, width: width, at: 1.40)
        #expect(p.fullSince == nil)
        let lifted = p.lift()
        #expect(!lifted)
    }

    @Test
    func anEventAfterALiftStartsANewPull() {
        var p = pulled(10)
        let travel = p.travel
        p.pull(lines: -0.5, width: width, at: 1.09 + NewSpaceWheelPull.liftPause + 0.05)
        #expect(travel > 20 && p.travel == 20)
    }
}
