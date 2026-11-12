import CraCEFWin
import CraCore
import Foundation
import WinAppSDK
import WinSDK
import WindowsFoundation

/// The clipboard, Windows' Share window and the Save dialog (CraCEFWin.h, MARK: Shell): what
/// NSPasteboard, NSSharingServicePicker and NSSavePanel do on the Mac.
@MainActor
enum WinShell {
    @MainActor
    private final class ShareRequest {
        let url: String
        let title: String
        let owner: UInt
        let dispatcher: WinAppSDK.DispatcherQueue
        let isValid: @MainActor () -> Bool
        let onFailure: @MainActor () -> Void
        var attempts = 0
        var timer: DispatcherQueueTimer?

        init(url: String, title: String, owner: UInt, dispatcher: WinAppSDK.DispatcherQueue,
             isValid: @escaping @MainActor () -> Bool, onFailure: @escaping @MainActor () -> Void) {
            self.url = url
            self.title = title
            self.owner = owner
            self.dispatcher = dispatcher
            self.isValid = isValid
            self.onFailure = onFailure
        }
    }
    private static var pendingShare: ShareRequest?
    /// Watches the window a Share sheet opened over (`watchOwner`).
    private static var ownerWatch: DispatcherQueueTimer?

    @discardableResult
    static func copy(_ text: String) -> Bool {
        text.withCString { cra_clipboard_set_text($0) } != 0
    }

    /// An image, as PNG and as a bitmap.
    @discardableResult
    static func copy(png: Data) -> Bool {
        png.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return cra_clipboard_set_png(base, raw.count) != 0
        }
    }

    /// Leave the caller's input callback before opening Share. A newer request supersedes
    /// an older busy one; its callbacks cannot reopen Share or report a stale failure.
    static func share(url: String, title: String, owner: UInt, dispatcher: WinAppSDK.DispatcherQueue,
                      isValid: @escaping @MainActor () -> Bool, onFailure: @escaping @MainActor () -> Void) {
        if let pendingShare { finishShare(pendingShare, failed: false) }
        let request = ShareRequest(url: url, title: title, owner: owner, dispatcher: dispatcher,
                                   isValid: isValid, onFailure: onFailure)
        pendingShare = request
        let queued = try? dispatcher.tryEnqueue { [weak request] in
            if let request { attemptShare(request) }
        }
        if queued != true { finishShare(request, failed: true) }
    }

    private static func attemptShare(_ request: ShareRequest) {
        guard pendingShare === request else { return }
        guard request.isValid() else { return finishShare(request, failed: false) }
        try? request.timer?.stop()
        request.timer = nil
        request.attempts += 1
        let result = request.url.withCString { u in
            request.title.withCString { t in cra_share_link_attempt(request.owner, u, t) }
        }
        // COM can pump messages: a newer request or a closed owner wins even if it happened
        // while this native call was returning.
        guard pendingShare === request else { return }
        guard request.isValid() else { return finishShare(request, failed: false) }
        let outcome: ShareRetry.Result
        switch result {
        case 1: outcome = .opened
        case 2: outcome = .busy
        default: outcome = .failed
        }
        switch ShareRetry.action(after: outcome, attempt: request.attempts) {
        case .opened:
            finishShare(request, failed: false)
            watchOwner(request)
        case .failed: finishShare(request, failed: true)
        case .retry(let delay):
            guard let timer = try? request.dispatcher.createTimer() else {
                return finishShare(request, failed: true)
            }
            do {
                request.timer = timer
                timer.interval = TimeSpan(duration: Int64(delay * 10_000_000))
                timer.isRepeating = false
                timer.tick.addHandler { [weak request] _, _ in
                    if let request { attemptShare(request) }
                }
                try timer.start()
            } catch {
                finishShare(request, failed: true)
            }
        }
    }

    /// The sheet disables the window it opens over. When it goes without enabling it again, or
    /// holds the front drawing nothing, the window would take no clicks or keys until Cra quits;
    /// when it never shows, the Share button would seem to do nothing. ShareRetry.OwnerWatch
    /// decides, every half second while the sheet may be up.
    private static func watchOwner(_ request: ShareRequest) {
        stopOwnerWatch()
        guard let owner = HWND(bitPattern: request.owner), let timer = try? request.dispatcher.createTimer() else { return }
        var watch = ShareRetry.OwnerWatch()
        timer.interval = TimeSpan(duration: Int64(ShareRetry.ownerCheckInterval * 10_000_000))
        timer.isRepeating = true
        // Holds the request: Share already let go of it (finishShare).
        timer.tick.addHandler { _, _ in
            guard IsWindow(owner) == true, request.isValid() else { return stopOwnerWatch() }
            let front = GetForegroundWindow() == GetAncestor(owner, UINT(GA_ROOT))
            let hidden = !front && cra_foreground_draws_nothing() != 0
            switch watch.next(ownerInFront: front, enabled: IsWindowEnabled(owner) == true, sheetHidden: hidden) {
            case .wait: break
            case .done: stopOwnerWatch()
            case .enable:
                print("Cra: Share left its window disabled; enabling it again")
                _ = EnableWindow(owner, true)
                stopOwnerWatch()
            case .notShown:
                print("Cra: Share reported success but no sheet showed")
                stopOwnerWatch()
                request.onFailure()
            }
        }
        ownerWatch = timer
        try? timer.start()
    }

    private static func stopOwnerWatch() {
        try? ownerWatch?.stop()
        ownerWatch = nil
    }

    private static func finishShare(_ request: ShareRequest, failed: Bool) {
        guard pendingShare === request else { return }
        try? request.timer?.stop()
        request.timer = nil
        pendingShare = nil
        if failed, request.isValid() { request.onFailure() }
    }

    /// A native menu at the pointer: `items` with nil for a separator. The chosen one's index.
    static func popupMenu(owner: UInt, _ items: [String?]) -> Int? {
        let copies: [UnsafeMutablePointer<CChar>?] = items.map { item in
            guard let item else { return nil }
            let utf8 = item.utf8CString
            let copy = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count)
            for (i, c) in utf8.enumerated() { copy[i] = c }
            return copy
        }
        defer { copies.forEach { $0?.deallocate() } }
        let pointers = copies.map { $0.map { UnsafePointer($0) } }
        let chosen = pointers.withUnsafeBufferPointer { cra_popup_menu(owner, $0.baseAddress, $0.count) }
        return chosen > 0 ? Int(chosen) - 1 : nil
    }

    /// Windows' Save dialog for a PNG, opening in Downloads; the chosen path, nil if cancelled.
    static func savePNG(owner: UInt, title: String, fileName: String) -> String? {
        let capacity = 4096
        var buffer = [CChar](repeating: 0, count: capacity)
        let chosen = title.withCString { t in
            fileName.withCString { f in cra_save_png_dialog(owner, t, f, &buffer, capacity) }
        }
        guard chosen != 0 else { return nil }
        return String(cString: buffer)
    }
}
