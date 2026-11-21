import CraCore
import Foundation
import WinAppSDK
import WinSDK
import WindowsFoundation

/// Arc's hidden sidebar (Ctrl+S): the window's edge brings it out over the page, and it goes
/// when the pointer leaves it (FloatingSidebar.swift on the Mac). The window's own XAML column is
/// what floats (HostWindow.floatingSidebar): one sidebar, docked or out.
///
/// The pointer is polled 30 times a second while the sidebar is hidden, as the Mac's floating
/// panel polls it; FloatingSidebarPointer decides from each look.
@MainActor
final class FloatingSidebar {
    private weak var window: HostWindow?
    private let dispatcher: WinAppSDK.DispatcherQueue
    /// The sidebar's width while it is out, in DIPs (the Library makes it wider).
    var width: Double = 280 { didSet { if width != oldValue { place() } } }
    /// The window's edge it comes out from (Settings ▸ Tabs ▸ Sidebar on the right).
    var side: SidebarSide = .left { didSet { if side != oldValue { place() } } }
    /// How the window presents its sidebar now.
    var presentation: () -> SidebarPresentation = { SidebarPresentation(sidebarVisible: true, hasSelectedTab: true) }
    /// Something the sidebar opened is up (the Library, a rename, a drag): it stays out.
    var keptOut: () -> Bool = { false }
    /// The sidebar went back out of sight.
    var onRetracted: (() -> Void)?

    private(set) var isOut = false
    /// Where its near edge is now, in DIPs from the window's edge on its side (a slide moves it;
    /// mirrored for a sidebar on the right).
    private var x: Double = 0
    private var pointer = FloatingSidebarPointer()
    private var poll: DispatcherQueueTimer?
    private var slide: DispatcherQueueTimer?
    private var slideStart = Date()
    private var slideFrom = 0.0, slideTo = 0.0

    /// How long the sidebar takes to come out or go. The Mac's reveal is a spring that settles in
    /// about 0.2 s (FloatingSidebarSpring); Windows slides on SidebarMotion's curve.
    static let slideDuration: TimeInterval = 0.16

    init(window: HostWindow, dispatcher: WinAppSDK.DispatcherQueue) {
        self.window = window
        self.dispatcher = dispatcher
    }

    /// The sidebar is hidden: start watching the pointer (and bring it out if the window holds it).
    func start() {
        guard poll == nil else { return }
        pointer.reset()
        isOut = false
        x = -(width + FloatingSidebarGeometry.margin)
        poll = try? dispatcher.createTimer()
        poll?.interval = TimeSpan(duration: 333_333)  // 30 Hz
        poll?.isRepeating = true
        poll?.tick.addHandler { [weak self] _, _ in self?.look() }
        try? poll?.start()
        look()
    }

    /// The sidebar is docked again: no floating, no watching.
    func stop() {
        try? poll?.stop()
        poll = nil
        stopSlide()
        isOut = false
        window?.floatingSidebar = nil
    }

    func show(animated: Bool = true) {
        guard !isOut, poll != nil else { return }
        isOut = true
        move(to: FloatingSidebarGeometry.margin, animated: animated)
    }

    func hide(animated: Bool = true) {
        guard isOut else { return }
        isOut = false
        move(to: -(width + FloatingSidebarGeometry.margin), animated: animated)
        onRetracted?()
    }

    /// One look at the pointer (FloatingSidebarPointer).
    private func look() {
        guard let window, let host = HWND(bitPattern: window.hwnd) else { return }
        let scale = window.scale
        let size = window.appWindow.clientSize
        let bounds = CGRect(x: 0, y: 0, width: Double(size.width) / scale, height: Double(size.height) / scale)
        var screen = POINT(x: Int32.min, y: Int32.min)
        let read = GetCursorPos(&screen)
        var client = screen
        if read { _ = ScreenToClient(host, &client) }
        let point = read ? CGPoint(x: Double(client.x) / scale, y: Double(client.y) / scale) : nil
        // A menu or popup the sidebar opened (an owned window under the pointer) keeps it out.
        var overOwnedPopup = false
        if read, let under = WindowFromPoint(screen) {
            let root = GetAncestor(under, UINT(GA_ROOT)), owner = GetAncestor(under, UINT(GA_ROOTOWNER))
            overOwnedPopup = owner == host && root != host
        }
        let front = GetForegroundWindow().map { GetAncestor($0, UINT(GA_ROOTOWNER)) == host } ?? false
        let buttons = [Int32(0x01), 0x02, 0x04].filter { GetAsyncKeyState($0) < 0 }.count
        let step = pointer.sample(point, in: bounds, sidebarWidth: CGFloat(width), isOut: isOut, presentation: presentation(),
                                  keptOut: overOwnedPopup || keptOut(), mayReveal: front && !IsIconic(host),
                                  pressedMouseButtons: buttons, edgeToEdge: true, side: side,
                                  at: ProcessInfo.processInfo.systemUptime)
        switch step {
        case .reveal: show()
        case .hide: hide()
        case .stay: break
        }
    }

    // MARK: Placing

    private func move(to target: Double, animated: Bool) {
        stopSlide()
        guard animated, x != target else {
            x = target
            place()
            return
        }
        slideFrom = x
        slideTo = target
        slideStart = Date()
        slide = try? dispatcher.createTimer()
        slide?.interval = TimeSpan(duration: 80_000)  // 125 Hz, under a frame at 60 Hz
        slide?.isRepeating = true
        slide?.tick.addHandler { [weak self] _, _ in self?.step() }
        try? slide?.start()
        step()
    }

    private func step() {
        let t = Date().timeIntervalSince(slideStart)
        let p = SidebarMotion.progress(at: t, duration: Self.slideDuration)
        x = slideFrom + (slideTo - slideFrom) * p
        if t >= Self.slideDuration {
            x = slideTo
            stopSlide()
        }
        place()
    }

    private func stopSlide() {
        try? slide?.stop()
        slide = nil
    }

    /// Puts the column where `x` says, or out of sight once it is all the way in.
    func place() {
        guard let window, poll != nil else { return }
        if !isOut && slide == nil {
            x = -(width + FloatingSidebarGeometry.margin)
            window.floatingSidebar = nil
            return
        }
        let scale = window.scale, height = window.appWindow.clientSize.height
        let margin = Int32((FloatingSidebarGeometry.margin * scale).rounded())
        window.floatingCornerRadius = Int32((12 * scale).rounded())
        let w = Int32((width * scale).rounded()), left = Int32((x * scale).rounded())
        let clientWidth = window.appWindow.clientSize.width
        window.floatingSidebar = PixelRect(x: side == .right ? clientWidth - left - w : left, y: margin,
                                           width: w, height: max(1, height - 2 * margin))
    }
}
