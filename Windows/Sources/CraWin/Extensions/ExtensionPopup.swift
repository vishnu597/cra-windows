import CraCore
import Foundation
import WinAppSDK
import WinSDK
import WinUI

/// An extension's popup page in a card of its own under the Site Control Center's sliders: what
/// ExtensionLaunch.popupWindow asks for when there is no toolbar for Chrome's own popup to hang
/// from, as on Windows (the Mac's ExtensionPopupWindow). It closes on Escape, when the page
/// closes itself (window.close()), and when another window becomes active, as Chrome's popups do.
@MainActor
final class ExtensionPopup {
    /// Chrome sizes a popup to its page, from 25 × 25 up to 800 × 600 DIPs; Cra gives it a
    /// size most popups fit for now.
    static let size = (width: 360.0, height: 480.0)

    private let window: HostWindow
    private var page: WebPage?
    private var closing = false
    /// After it closed, for its owner to let go of it.
    var onClose: (() -> Void)?
    /// A link the popup opens in a tab (target=_blank, Ctrl-click): its owner's tab.
    var openTab: ((String) -> Void)?

    /// Opens `url` in `profilePath`'s profile, its top right corner at `corner` (screen pixels).
    init(url: String, profilePath: String?, owner: HostWindow, corner: POINT) throws {
        window = try HostWindow(content: Grid(), sidebarWidth: 0, owner: owner)
        window.background = HostColor(r: 255, g: 255, b: 255)
        let scale = owner.scale
        let width = Int32((Self.size.width * scale).rounded()), height = Int32((Self.size.height * scale).rounded())
        window.placeClient(x: max(0, corner.x - width), y: corner.y, width: width, height: height)
        window.onDeactivate = { [weak self] in self?.close() }
        window.onClose = { [weak self] in self?.close() }
        window.onLayout = { [weak self] frame in self?.page?.frame = frame }
        page = WebPage(parent: window.hwnd, frame: window.contentFrame, url: url, profilePath: profilePath, delegate: self)
        window.activate()
        page?.setFocused(true)
    }

    /// Deferred a turn: it is often asked from inside the window's own messages (its
    /// deactivation, a key), and a window destroyed there crashed Cra (PR #18). The queued work
    /// holds the popup until then, as its owner may have let go of it already.
    func close() {
        guard !closing else { return }
        closing = true
        _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { self.finish() }
    }

    private func finish() {
        let page = self.page
        self.page = nil
        page?.close()
        window.onClose = nil
        window.onDeactivate = nil
        window.close()
        onClose?()
    }
}

extension ExtensionPopup: WebPageDelegate {
    func page(_ page: WebPage, handleKey key: KeyPress) -> Bool {
        guard key.keyCode == 0x1B, !key.control, !key.alt, !key.shift else { return false }
        close()
        return true
    }

    func page(_ page: WebPage, requestsNewTabWithURL url: String, inBackground background: Bool) {
        openTab?(url)
        close()
    }

    func page(_ page: WebPage, popupHostForURL url: String, inBackground background: Bool) -> WebPage? {
        openTab?(url)
        close()
        return nil
    }

    func pageDidClose(_ page: WebPage) {
        guard self.page === page else { return }
        self.page = nil
        close()
    }
}
