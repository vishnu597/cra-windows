import CraCore
import Foundation
import Testing

/// The ring on the download bin (#272) as Windows draws it.
struct DownloadBadgeTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private func live(_ id: UInt32, received: Int64, total: Int64, failed: Bool = false, cancelled: Bool = false) -> DownloadList.Live {
        var l = DownloadList.Live(id: id, name: "file.zip", path: "", started: now, received: received, total: total,
                                  percent: total > 0 ? Int(received * 100 / total) : 0, updated: now)
        l.moved = now
        l.failed = failed
        l.cancelled = cancelled
        return l
    }

    @Test func ringFollowsRunningDownloadsThenChecks() {
        var badge = DownloadBadge()
        #expect(badge.look == .hidden)
        let changed = badge.update([live(1, received: 25, total: 100)], now: now)
        #expect(changed)
        #expect(badge.look == .running(0.25))
        badge.update([live(1, received: 50, total: 100), live(2, received: 0, total: 100)], now: now)
        #expect(badge.look == .running(0.25), "both downloads together")
        badge.update([live(2, received: 100, total: 200)], now: now)
        #expect(badge.look == .running(0.5))
        badge.update([], now: now)
        #expect(badge.look == .done, "every followed download finished with its file: the check")
        badge.doneShown()
        #expect(badge.look == .hidden)
    }

    @Test func failedOrCancelledJustGoes() {
        var badge = DownloadBadge()
        badge.update([live(1, received: 10, total: 100)], now: now)
        badge.update([live(1, received: 10, total: 100, failed: true)], now: now)
        #expect(badge.look == .hidden, "no check for a failed download")

        badge.update([live(2, received: 10, total: 100)], now: now)
        badge.update([live(2, received: 10, total: 100, cancelled: true)], now: now)
        #expect(badge.look == .hidden, "nor for a cancelled one")
    }

    /// The bin's #491 rule: a download stuck at 0 bytes doesn't keep the badge.
    @Test func stuckDownloadDoesNotHoldTheRing() {
        var badge = DownloadBadge()
        badge.update([live(1, received: 0, total: 0)], now: now)
        #expect(badge.look == .running(0))
        let later = now.addingTimeInterval(DownloadList.stuckAfter + 1)
        badge.update([live(1, received: 0, total: 0)], now: later)
        #expect(badge.look == .hidden, "still running, but stuck: the row keeps it, the badge goes")
    }

    @Test func newDownloadDuringTheCheckKeepsItsRing() {
        var badge = DownloadBadge()
        badge.update([live(1, received: 1, total: 2)], now: now)
        badge.update([], now: now)
        #expect(badge.look == .done)
        badge.update([live(3, received: 1, total: 4)], now: now)
        #expect(badge.look == .running(0.25))
        badge.doneShown()
        #expect(badge.look == .running(0.25))
        let finished = badge.update([], now: now)
        #expect(finished, "the ring's download finished")
        #expect(badge.look == .done)
    }
}
