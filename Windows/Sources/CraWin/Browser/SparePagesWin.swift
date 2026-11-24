import CraCore
import Foundation

/// One Chromium page per profile made ahead, which the next tab that needs a page takes (CraCore's
/// SparePage, the Mac's SparePages, upstream 935cca1): making a page's window then falls between
/// clicks, not on one. Shared by every browser window. A spare has no delegate and no tab, is
/// hidden in the window that made it, and has nothing loaded, so the tab's address is the first
/// page of its history.
@MainActor
final class SparePagesWin {
    static let shared = SparePagesWin()

    /// CRA_SPARE_PAGES=0 turns spares off (for measuring), as on the Mac.
    static let isEnabled = ProcessInfo.processInfo.environment["CRA_SPARE_PAGES"] != "0"

    private var spares: [String: (page: WebPage, parent: UInt)] = [:]
    private var pending: [String: ScheduledWork] = [:]

    /// A spare for `profilePath` that Chromium has finished making, or nil. It is no longer kept.
    func take(profilePath: String?) -> WebPage? {
        let key = SparePage.key(profilePath: profilePath)
        guard Self.isEnabled, let spare = spares[key], spare.page.isCreated, !spare.page.isClosed else { return nil }
        spares[key] = nil
        return spare.page
    }

    /// Makes `profilePath`'s next spare in `parent` `SparePage.refillDelay` from now, unless it has one.
    func refill(profilePath: String?, parent: UInt, frame: PixelRect, clock: Scheduler) {
        let key = SparePage.key(profilePath: profilePath)
        guard Self.isEnabled, spares[key] == nil, pending[key] == nil else { return }
        pending[key] = clock.after(SparePage.refillDelay) { [weak self] in
            guard let self else { return }
            self.pending[key] = nil
            if let old = self.spares[key], !old.page.isClosed { return }
            let page = WebPage(spareIn: parent, frame: frame, profilePath: profilePath)
            page.isVisible = false
            self.spares[key] = (page, parent)
        }
    }

    /// A window is closing: the spares it holds go with it, and its pending refills.
    func drop(parent: UInt) {
        for (key, spare) in spares where spare.parent == parent {
            spare.page.close()
            spares[key] = nil
        }
        // A refill made by this window would make its page in it: let the next window refill.
        for work in pending.values { work.cancel() }
        pending = [:]
    }
}
