import Foundation

/// The app's `Scheduler` (CraCore): wall-clock time and Timers on the main run loop.
@MainActor
final class LiveScheduler: Scheduler {
    static let shared = LiveScheduler()

    var now: Date { Date() }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        timer(delay, repeats: false, work)
    }

    func every(_ interval: TimeInterval, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        timer(interval, repeats: true, work)
    }

    private func timer(_ interval: TimeInterval, repeats: Bool, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        var timer: Timer?
        let handle = ScheduledWork { timer?.invalidate() }
        // A fire already queued on the main actor when the work is cancelled does not run. The
        // handle is weak so it isn't kept alive by its own timer, and a handle nobody kept still
        // runs: only cancel() stops the work (a dropped `after` used to never fire).
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { [weak handle] _ in
            Task { @MainActor in if handle?.isCancelled != true { work() } }
        }
        return handle
    }
}
