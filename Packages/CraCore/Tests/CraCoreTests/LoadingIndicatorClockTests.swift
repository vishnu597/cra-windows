import CraCore
import Testing

/// The loading bar's frames for a platform that draws them itself (Windows), following the Mac's
/// LoadingIndicatorView step for step.
struct LoadingIndicatorClockTests {
    private func near(_ a: Double?, _ b: Double, _ tolerance: Double = 0.001) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance
    }

    @Test func hiddenDrawsNothing() {
        let clock = LoadingIndicator.Clock()
        #expect(clock.phase == .hidden)
        #expect(clock.frame(at: 0) == nil)
        #expect(!clock.isRunning(at: 0))
    }

    @Test func waitingPulsesThePill() throws {
        var clock = LoadingIndicator.Clock()
        clock.set(.waiting, animated: true, at: 10)
        let start = try #require(clock.frame(at: 10))
        #expect(start.width == LoadingIndicator.pillWidth && start.lit && start.segmentStart == nil)
        #expect(near(start.opacity, 0))
        // Full at 0.7 s, gone again at 1.35 s, still off at 1.5 s, then the next pulse.
        #expect(near(clock.frame(at: 10.7)?.opacity, 1))
        #expect(near(clock.frame(at: 11.35)?.opacity, 0))
        #expect(near(clock.frame(at: 11.5)?.opacity, 0))
        #expect(near(clock.frame(at: 10 + 1.6 + 0.7)?.opacity, 1))
        // Eased: a quarter of the way in is less than a quarter lit.
        let quarter = try #require(clock.frame(at: 10 + 0.7 / 4)?.opacity)
        #expect(quarter > 0 && quarter < 0.25)
        #expect(clock.isRunning(at: 100))
    }

    @Test func committedPillWidensThenSweepsFromItsTail() throws {
        var clock = LoadingIndicator.Clock()
        clock.set(.waiting, animated: true, at: 0)
        clock.set(.loading, animated: true, at: 0.7)
        let start = try #require(clock.frame(at: 0.7))
        #expect(near(start.width, LoadingIndicator.pillWidth) && start.lit && near(start.opacity, 1))
        let mid = try #require(clock.frame(at: 0.7 + LoadingIndicator.expandDuration / 2))
        #expect(mid.width > LoadingIndicator.pillWidth && mid.width < LoadingIndicator.trackWidth && mid.lit)
        // Once wide, the sweep picks up lit end to end, with the tail setting off.
        let swept = try #require(clock.frame(at: 0.7 + LoadingIndicator.expandDuration))
        #expect(swept.width == LoadingIndicator.trackWidth && !swept.lit)
        #expect(near(swept.segmentStart, 0) && near(swept.segmentEnd, 1))
        let later = try #require(clock.frame(at: 0.7 + LoadingIndicator.expandDuration + 0.1))
        #expect(later.segmentStart! > 0 && near(later.segmentEnd, 1))
    }

    @Test func loadingWithoutWaitingSweepsFromTheStart() throws {
        var clock = LoadingIndicator.Clock()
        clock.set(.loading, animated: true, at: 5)
        let start = try #require(clock.frame(at: 5))
        #expect(start.width == LoadingIndicator.trackWidth && !start.lit && near(start.opacity, 0))
        #expect(near(start.segmentStart, 0) && near(start.segmentEnd, 0))
        #expect(near(clock.frame(at: 5 + LoadingIndicator.Clock.fadeInDuration)?.opacity, 1))
        let head = try #require(clock.frame(at: 5 + 0.37 / 2))
        #expect(near(head.segmentStart, 0) && near(head.segmentEnd, 0.5, 0.01))
        // Not animated (another tab came to the front): no fade-in.
        var other = LoadingIndicator.Clock()
        other.set(.loading, animated: false, at: 5)
        #expect(near(other.frame(at: 5)?.opacity, 1))
    }

    @Test func doneFlashesAndShrinksAway() throws {
        var clock = LoadingIndicator.Clock()
        clock.set(.loading, animated: false, at: 0)
        clock.set(.hidden, animated: true, at: 2)
        let flash = try #require(clock.frame(at: 2))
        #expect(flash.lit && near(flash.opacity, 1) && near(flash.width, LoadingIndicator.trackWidth))
        let mid = try #require(clock.frame(at: 2 + LoadingIndicator.finishDuration / 2))
        #expect(mid.width < LoadingIndicator.trackWidth && mid.width > LoadingIndicator.finishWidth && mid.opacity < 1)
        #expect(clock.frame(at: 2 + LoadingIndicator.finishDuration) == nil)
        #expect(!clock.isRunning(at: 2 + LoadingIndicator.finishDuration))
    }

    @Test func unansweredPillJustFades() throws {
        var clock = LoadingIndicator.Clock()
        clock.set(.waiting, animated: true, at: 0)
        clock.set(.hidden, animated: true, at: 0.7)
        let fade = try #require(clock.frame(at: 0.7))
        #expect(fade.width == LoadingIndicator.pillWidth && near(fade.opacity, 1))
        #expect(clock.frame(at: 0.7 + LoadingIndicator.Clock.waitingFadeDuration) == nil)
        // A tab switch hides it at once.
        var switched = LoadingIndicator.Clock()
        switched.set(.loading, animated: false, at: 0)
        switched.set(.hidden, animated: false, at: 1)
        #expect(switched.frame(at: 1) == nil)
    }

    @Test func easesMatchCoreAnimation() {
        for ease in [LoadingIndicator.Ease.easeIn, LoadingIndicator.Ease.easeOut, LoadingIndicator.Ease.easeInOut] {
            #expect(near(ease(0), 0) && near(ease(1), 1))
        }
        #expect(near(LoadingIndicator.Ease.easeInOut(0.5), 0.5))
        #expect(LoadingIndicator.Ease.easeIn(0.25) < 0.25 && LoadingIndicator.Ease.easeOut(0.25) > 0.25)
    }
}
