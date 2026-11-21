import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WinUI

/// A top-level window with XAML in its sidebar column (and a strip over the page area when
/// asked: the Developer Mode bar) and Chromium's pages beside it.
///
/// Not a WinUI `Window`: a Window's XAML bridge always covers its whole client area, and WinUI
/// then takes every real click and wheel meant for a page under it, even with the page above it
/// in z-order. (Found on a PC: clicks reached the page whenever the bridge didn't cover it, and
/// never while it did; keys were fine once the page had focus.) So this is an AppWindow with a
/// DesktopWindowXamlSource whose bridge it keeps to the sidebar.
///
/// Main thread only, like the XAML it holds (not marked @MainActor so the app's nonisolated
/// WinUI callbacks can use it directly).
final class HostWindow {
    let appWindow: AppWindow
    /// Every page is a child window of it.
    let hwnd: UInt
    private let xaml = DesktopWindowXamlSource()
    /// The strip over the page area, a second island so it covers no page (see above).
    private let topXaml = DesktopWindowXamlSource()

    /// The XAML column's width, in DIPs.
    var sidebarWidth: Double { didSet { layout() } }
    /// Which side of the window the column docks on (Settings ▸ Tabs ▸ Sidebar on the right):
    /// on the right the pages start at the window's left edge.
    var sidebarSide: SidebarSide = .left { didSet { if sidebarSide != oldValue { layout() } } }
    /// The XAML column floated over the pages (the hidden sidebar brought out), in physical pixels
    /// relative to the client area; nil keeps it in its column. Set it with `sidebarWidth` at 0:
    /// the pages then fill the window and the column sits over their left edge.
    var floatingSidebar: PixelRect? { didSet { if floatingSidebar != oldValue { layout() } } }
    /// Where the XAML column's top left is in the client area, in physical pixels: XAML's own
    /// coordinates start there.
    var columnOrigin: (x: Int32, y: Int32) {
        floatingSidebar.map { ($0.x, $0.y) } ?? (sidebarSide == .right ? appWindow.clientSize.width - dockedColumnWidth : 0, 0)
    }
    /// The docked column's width in physical pixels (0 when it isn't docked).
    private var dockedColumnWidth: Int32 {
        min(appWindow.clientSize.width, Int32((sidebarWidth * scale).rounded()))
    }
    /// The floating column's corner radius, in physical pixels.
    var floatingCornerRadius: Int32 = 16
    /// The strip's height over the page area, in DIPs; 0 hides it and the pages fill the area.
    var topBarHeight: Double = 0 { didSet { if topBarHeight != oldValue { layout() } } }
    /// After every resize, with the page area (`contentFrame`).
    var onLayout: ((PixelRect) -> Void)?
    /// The window moved on screen (what floats over it follows).
    var onMove: (() -> Void)?
    /// The user asked to close (title bar, Alt+F4). Return false to keep the window open for
    /// now and call `close()` later.
    var shouldClose: (() -> Bool)?
    /// The window is going away.
    var onClose: (() -> Void)?
    /// The keyboard came to the window itself rather than a page or the sidebar: Windows does
    /// that when the window becomes active (at launch, Alt+Tab back, a dialog or the command bar
    /// going away). Give it to what should have it, or keys go nowhere.
    var onFocus: (() -> Void)?
    /// The window became the active one (a click, Alt+Tab, the taskbar): the store's active
    /// window follows it, as AppKit's key window does on the Mac.
    var onActivate: (() -> Void)?
    /// Another window became the active one (an extension's popup closes then, as Chrome's do).
    var onDeactivate: (() -> Void)?
    /// The window's active look changed (`activeLook`).
    var onActiveLookChanged: ((Bool) -> Void)?
    /// Whether the sidebar draws its active look: Cra is the active app, the window isn't minimized,
    /// and it or a window it owns (the command bar, a dialog) is the active one, as a Mac window's
    /// child windows count as the window (SidebarBackdrop.windowActive).
    private(set) var activeLook = true
    private var appActive = true, holdsActive = true

    /// A move or resize by the user ended (its frame is then worth saving).
    var onMoveEnded: (() -> Void)?
    /// The window's own client area shows wherever no page and no XAML covers it: between split
    /// panes and in an empty pane. It is painted in this colour.
    var background: HostColor = HostColor(r: 28, g: 36, b: 43) { didSet { if background != oldValue { invalidate() } } }
    /// A rounded bar drawn on that area (a split divider being dragged), in `pillColor`.
    var pill: PixelRect? { didSet { if pill != oldValue { invalidate() } } }
    var pillColor = HostColor(r: 0, g: 0, b: 0)
    /// The mouse on that area, in physical pixels relative to the client area. A press captures
    /// the mouse, so moves and the release come here until it is let go.
    var onMouse: ((HostMouseEvent) -> Void)?
    /// The pointer's shape over that area at a client point; nil leaves the arrow.
    var cursor: ((Int32, Int32) -> HostCursor?)?
    private var closed = false
    /// The floating column's rounded region is for this size (placeColumn).
    private var lastRegionSize: [Int32]?
    private var lastPress: (time: Int32, x: Int32, y: Int32)?
    /// The window procedure below is a C function and can't capture its window. Kept after the
    /// window object goes: Windows still sends the window messages while destroying it.
    nonisolated(unsafe) private static var hooks: [UInt: Hook] = [:]
    private struct Hook {
        let previous: WNDPROC?
        weak var window: HostWindow?
    }

    /// `frame`: where to open, in screen pixels (a restored or cascaded window); nil opens a
    /// `width` × `height` window where Windows puts it.
    /// `topBar`: what the strip over the page area shows while `topBarHeight` isn't 0.
    /// `owner`: a card over that window (the Peek): a border without a title bar, which Windows 11
    /// rounds and shadows, never on the taskbar or in Alt+Tab, always over its owner. It opens
    /// hidden; `placeClient` puts it on screen.
    init(content: UIElement, topBar: UIElement? = nil, sidebarWidth: Double, frame: WindowFrame? = nil,
         width: Double = 1280, height: Double = 820, owner: HostWindow? = nil) throws {
        if let owner {
            guard let presenter = try OverlappedPresenter.create() else { throw FloatingWindowError.noPresenter }
            presenter.isResizable = false
            presenter.isMaximizable = false
            presenter.isMinimizable = false
            try presenter.setBorderAndTitleBar(true, false)
            guard let window = try AppWindow.create(presenter, owner.appWindow.id) else { throw FloatingWindowError.noWindow }
            appWindow = window
            appWindow.isShownInSwitchers = false
        } else {
            appWindow = try AppWindow.create()
        }
        isCard = owner != nil
        hwnd = UInt(appWindow.id.value)
        self.sidebarWidth = sidebarWidth
        try xaml.initialize(appWindow.id)
        xaml.content = content
        if let topBar {
            try topXaml.initialize(appWindow.id)
            topXaml.content = topBar
        }
        appWindow.changed.addHandler { [weak self] _, args in
            if args?.didSizeChange == true { self?.layout() }
            if args?.didPositionChange == true { self?.onMove?() }
        }
        appWindow.closing.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            // Destroyed by close(), after this event rather than inside it.
            args.cancel = true
            if self.shouldClose?() ?? true {
                _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { [weak self] in self?.close() }
            }
        }
        if isCard {
            // Placed and shown by its owner (placeClient).
        } else if let frame {
            try appWindow.moveAndResize(RectInt32(x: Int32(frame.x.rounded()), y: Int32(frame.y.rounded()),
                                                  width: Int32(frame.width.rounded()), height: Int32(frame.height.rounded())))
        } else {
            try appWindow.resize(SizeInt32(width: Int32(width * scale), height: Int32(height * scale)))
        }
        layout()
        hookWindowProcedure()
        if !isCard {
            WindowIcon.apply(to: hwnd)
            try appWindow.show()
        }
    }

    /// An owned card (init's `owner`).
    let isCard: Bool

    /// Puts the client area at `x, y` on screen, `width` × `height` physical pixels, and shows the
    /// window (FloatingWindow.place: the frame's borders sit outside that area).
    func placeClient(x: Int32, y: Int32, width: Int32, height: Int32) {
        guard !closed else { return }
        let size = SizeInt32(width: max(width, 1), height: max(height, 1))
        try? appWindow.resizeClient(size)
        let client = appWindow.clientSize
        if client.width != size.width || client.height != size.height {
            let outer = appWindow.size
            try? appWindow.resize(SizeInt32(width: outer.width - (client.width - size.width), height: outer.height - (client.height - size.height)))
        }
        guard let window = HWND(bitPattern: hwnd) else { return }
        var origin = POINT(x: 0, y: 0), frame = RECT()
        _ = ClientToScreen(window, &origin)
        _ = GetWindowRect(window, &frame)
        try? appWindow.move(PointInt32(x: x - (origin.x - frame.left), y: y - (origin.y - frame.top)))
        if !appWindow.isVisible { try? appWindow.show(true) }
        layout()
    }

    /// Puts the window just below `other` among its owner's windows (0: in front of them all),
    /// without moving or activating it.
    func order(below other: UInt) {
        guard let window = HWND(bitPattern: hwnd) else { return }
        let noSize: UINT = 0x0001, noMove: UINT = 0x0002, noActivate: UINT = 0x0010, noOwnerZOrder: UINT = 0x0200
        _ = SetWindowPos(window, other == 0 ? HWND(bitPattern: 0) : HWND(bitPattern: other), 0, 0, 0, 0,
                         noSize | noMove | noActivate | noOwnerZOrder)
    }

    /// Arc's Stay On Top: the window stays above other apps' windows (HWND_TOPMOST), or goes back
    /// among them (the Mac's floating window level).
    var staysOnTop: Bool {
        get {
            guard let window = HWND(bitPattern: hwnd) else { return false }
            return GetWindowLongPtrW(window, GWL_EXSTYLE) & LONG_PTR(Self.topmost) != 0
        }
        set {
            guard let window = HWND(bitPattern: hwnd) else { return }
            let noSize: UINT = 0x0001, noMove: UINT = 0x0002, noActivate: UINT = 0x0010
            _ = SetWindowPos(window, HWND(bitPattern: newValue ? -1 : -2), 0, 0, 0, 0, noSize | noMove | noActivate)
        }
    }
    private static let topmost: UInt32 = 0x0000_0008  // WS_EX_TOPMOST

    var title: String {
        get { appWindow.title }
        set { appWindow.title = newValue }
    }

    /// The window's outer frame on screen, in physical pixels.
    var frame: WindowFrame {
        let p = appWindow.position, s = appWindow.size
        return WindowFrame(x: Double(p.x), y: Double(p.y), width: Double(s.width), height: Double(s.height))
    }

    /// The work area (the screen less the taskbar) of the monitor the window is on.
    var workArea: WindowFrame? {
        guard let window = HWND(bitPattern: hwnd), let monitor = MonitorFromWindow(window, DWORD(MONITOR_DEFAULTTONEAREST)) else { return nil }
        return HostWindow.workArea(of: monitor)
    }

    /// Every monitor's work area (where a restored window may open).
    static var workAreas: [WindowFrame] {
        var areas: [WindowFrame] = []
        let collect: MONITORENUMPROC = { monitor, _, _, context in
            guard let monitor, let list = UnsafeMutablePointer<[WindowFrame]>(bitPattern: Int(context)),
                  let area = HostWindow.workArea(of: monitor) else { return true }
            list.pointee.append(area)
            return true
        }
        withUnsafeMutablePointer(to: &areas) { pointer in
            _ = EnumDisplayMonitors(nil, nil, collect, LPARAM(Int(bitPattern: pointer)))
        }
        return areas
    }

    /// The work area of the monitor under the pointer (where a Little Window opens).
    static var workAreaUnderPointer: WindowFrame? {
        var p = POINT()
        guard GetCursorPos(&p), let monitor = MonitorFromPoint(p, DWORD(MONITOR_DEFAULTTONEAREST)) else { return nil }
        return workArea(of: monitor)
    }

    private static func workArea(of monitor: HMONITOR) -> WindowFrame? {
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard GetMonitorInfoW(monitor, &info) else { return nil }
        let r = info.rcWork
        return WindowFrame(x: Double(r.left), y: Double(r.top), width: Double(r.right - r.left), height: Double(r.bottom - r.top))
    }

    /// Brings the window to the front with the keyboard.
    func activate() {
        guard let window = HWND(bitPattern: hwnd) else { return }
        if IsIconic(window) { _ = ShowWindow(window, SW_RESTORE) }
        _ = SetForegroundWindow(window)
    }

    /// Physical pixels per DIP.
    var scale: Double {
        guard let window = HWND(bitPattern: hwnd) else { return 1 }
        let dpi = GetDpiForWindow(window)
        return dpi > 0 ? Double(dpi) / 96 : 1
    }

    /// The page area: beside the sidebar and under the top strip, in physical pixels relative
    /// to the client area.
    var contentFrame: PixelRect {
        let size = appWindow.clientSize
        let column = dockedColumnWidth
        let y = min(size.height, Int32((topBarHeight * scale).rounded()))
        return PixelRect(x: sidebarSide == .right ? 0 : column, y: y, width: size.width - column, height: size.height - y)
    }

    /// Moves Win32 focus into the top strip's XAML, for a programmatic XAML focus to take.
    func focusTopBar() {
        guard let bridge = topXaml.siteBridge, let window = HWND(bitPattern: UInt(bridge.windowId.value)) else { return }
        _ = SetFocus(window)
    }

    /// Moves Win32 focus into the XAML column (from a page), for a programmatic XAML focus to
    /// take.
    func focusXAML() {
        guard let bridge = xaml.siteBridge, let window = HWND(bitPattern: UInt(bridge.windowId.value)) else { return }
        _ = SetFocus(window)
    }

    /// Hears messages ahead of AppWindow's own window procedure: WM_SETFOCUS, which it ignores,
    /// and the painting and mouse of the client area the pages and XAML leave uncovered.
    private func hookWindowProcedure() {
        guard let window = HWND(bitPattern: hwnd) else { return }
        // Painting the uncovered area must not paint over the pages.
        let style = GetWindowLongPtrW(window, GWL_STYLE)
        _ = SetWindowLongPtrW(window, GWL_STYLE, style | LONG_PTR(Self.clipChildren))
        let proc: WNDPROC = { hwnd, message, wParam, lParam in
            guard let hook = HostWindow.hooks[UInt(bitPattern: hwnd)], let previous = hook.previous else {
                return DefWindowProcW(hwnd, message, wParam, lParam)
            }
            if let window = hook.window, let handled = window.handle(message, wParam, lParam) { return handled }
            let result = CallWindowProcW(previous, hwnd, message, wParam, lParam)
            if message == UINT(WM_SETFOCUS) { hook.window?.onFocus?() }
            return result
        }
        let previous = SetWindowLongPtrW(window, GWLP_WNDPROC, unsafeBitCast(proc, to: LONG_PTR.self))
        Self.hooks[hwnd] = Hook(previous: unsafeBitCast(previous, to: WNDPROC?.self), window: self)
    }

    // Message numbers and constants, spelled out: WinSDK imports some as macros Swift can't see.
    private static let wmSetCursor: UINT = 0x0020, wmPaint: UINT = 0x000F, wmEraseBackground: UINT = 0x0014
    private static let wmMouseMove: UINT = 0x0200, wmLeftDown: UINT = 0x0201, wmLeftUp: UINT = 0x0202
    private static let wmCaptureChanged: UINT = 0x0215
    private static let wmActivate: UINT = 0x0006, wmExitSizeMove: UINT = 0x0232, wmActivateApp: UINT = 0x001C
    private static let clipChildren: UInt32 = 0x0200_0000  // WS_CLIPCHILDREN
    private static let hitClient = 1  // HTCLIENT
    private static let doubleClickWidth: Int32 = 36, doubleClickHeight: Int32 = 37  // SM_CXDOUBLECLK, SM_CYDOUBLECLK

    /// Whether `other` is this window or one it owns, directly or through another owned window.
    private func owns(_ other: UInt) -> Bool {
        guard other != 0, let w = HWND(bitPattern: other), let root = GetAncestor(w, UINT(GA_ROOTOWNER)) else { return false }
        return UInt(bitPattern: root) == hwnd
    }

    private func updateActiveLook() {
        let iconic = HWND(bitPattern: hwnd).map { IsIconic($0) } ?? false
        let look = SidebarBackdrop.windowActive(appActive: appActive, miniaturized: iconic, holdsKeyOrMain: holdsActive)
        guard look != activeLook else { return }
        activeLook = look
        onActiveLookChanged?(look)
    }

    /// The result for a message this window answers itself; nil passes it on to AppWindow's.
    private func handle(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch message {
        case Self.wmEraseBackground:
            return 1  // WM_PAINT fills it, without a flash of the class background first
        case Self.wmPaint:
            paint()
            return 0
        case Self.wmSetCursor:
            // Over a page or the XAML, wParam is that child window: it keeps its own pointer.
            guard UInt(wParam) == hwnd, Int(lParam & 0xFFFF) == Self.hitClient, let window = HWND(bitPattern: hwnd) else { return nil }
            var p = POINT()
            _ = GetCursorPos(&p)
            _ = ScreenToClient(window, &p)
            guard let shape = cursor?(p.x, p.y) else { return nil }
            _ = SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: shape.rawValue)))
            return 1
        case Self.wmLeftDown:
            let (x, y) = Self.point(lParam)
            let time = GetMessageTime()
            var clicks = 1
            if let last = lastPress, UInt32(bitPattern: time &- last.time) <= GetDoubleClickTime(),
               abs(x - last.x) <= GetSystemMetrics(Self.doubleClickWidth) / 2, abs(y - last.y) <= GetSystemMetrics(Self.doubleClickHeight) / 2 {
                clicks = 2
            }
            lastPress = clicks == 2 ? nil : (time, x, y)
            if let window = HWND(bitPattern: hwnd) { _ = SetCapture(window) }
            onMouse?(.down(x: x, y: y, clicks: clicks))
            return 0
        case Self.wmMouseMove:
            let (x, y) = Self.point(lParam)
            onMouse?(.move(x: x, y: y))
            return nil
        case Self.wmLeftUp:
            let (x, y) = Self.point(lParam)
            onMouse?(.up(x: x, y: y))
            _ = ReleaseCapture()
            return 0
        case Self.wmCaptureChanged:
            // Taken away mid-drag (Alt+Tab, a menu): the drag ends where it is.
            onMouse?(.cancelled)
            return nil
        case Self.wmActivate:
            // WA_INACTIVE is 0; WA_ACTIVE and WA_CLICKACTIVE are not.
            let activated = wParam & 0xFFFF != 0
            // Going inactive, lParam is the window becoming active: one this window owns keeps the look.
            holdsActive = activated || owns(UInt(bitPattern: Int(lParam)))
            updateActiveLook()
            if activated { onActivate?() } else { onDeactivate?() }
            return nil
        case Self.wmActivateApp:
            appActive = wParam != 0
            if appActive { holdsActive = owns(GetForegroundWindow().map { UInt(bitPattern: $0) } ?? 0) || holdsActive }
            updateActiveLook()
            return nil
        case Self.wmExitSizeMove:
            onMoveEnded?()
            return nil
        default:
            return nil
        }
    }

    /// The client point a mouse message carries (signed: a captured drag goes past the edges).
    private static func point(_ lParam: LPARAM) -> (Int32, Int32) {
        (Int32(Int16(truncatingIfNeeded: lParam & 0xFFFF)), Int32(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF)))
    }

    private func paint() {
        guard let window = HWND(bitPattern: hwnd) else { return }
        var ps = PAINTSTRUCT()
        guard let dc = BeginPaint(window, &ps) else { return }
        if let brush = CreateSolidBrush(background.colorRef) {
            _ = FillRect(dc, &ps.rcPaint, brush)
            _ = DeleteObject(UnsafeMutableRawPointer(brush))
        }
        if let pill, pill.width > 0, pill.height > 0, let brush = CreateSolidBrush(pillColor.colorRef) {
            let round = min(pill.width, pill.height)
            if let region = CreateRoundRectRgn(pill.x, pill.y, pill.x + pill.width + 1, pill.y + pill.height + 1, round, round) {
                _ = FillRgn(dc, region, brush)
                _ = DeleteObject(UnsafeMutableRawPointer(region))
            }
            _ = DeleteObject(UnsafeMutableRawPointer(brush))
        }
        _ = EndPaint(window, &ps)
    }

    private func invalidate() {
        guard !closed, let window = HWND(bitPattern: hwnd) else { return }
        _ = InvalidateRect(window, nil, false)
    }

    func close() {
        guard !closed else { return }
        closed = true
        onClose?()
        try? topXaml.close()
        try? xaml.close()
        try? appWindow.destroy()
    }

    private func layout() {
        guard !closed else { return }
        let frame = contentFrame, height = appWindow.clientSize.height
        placeColumn(frame: frame, height: height)
        if let bridge = topXaml.siteBridge, let strip = HWND(bitPattern: UInt(bridge.windowId.value)) {
            if frame.y > 0 {
                try? bridge.moveAndResize(RectInt32(x: frame.x, y: 0, width: frame.width, height: frame.y))
                _ = ShowWindow(strip, SW_SHOWNA)
            } else {
                _ = ShowWindow(strip, SW_HIDE)
            }
        }
        onLayout?(frame)
    }
}

extension HostWindow {
    /// The XAML column beside the pages, floated over them, or out of sight when the sidebar is
    /// hidden and not out. A child window over a page draws over it and takes the clicks there
    /// (the pages are its siblings), so the floating column needs no window of its own.
    private func placeColumn(frame: PixelRect, height: Int32) {
        guard let bridge = xaml.siteBridge, let column = HWND(bitPattern: UInt(bridge.windowId.value)) else { return }
        if let float = floatingSidebar, float.width > 0, float.height > 0 {
            try? bridge.moveAndResize(RectInt32(x: float.x, y: float.y, width: float.width, height: float.height))
            let r = floatingCornerRadius
            if lastRegionSize != [float.width, float.height], let region = CreateRoundRectRgn(0, 0, float.width + 1, float.height + 1, r, r) {
                // The window owns the region from here on.
                _ = SetWindowRgn(column, region, true)
                lastRegionSize = [float.width, float.height]
            }
            _ = ShowWindow(column, SW_SHOWNA)
            // Over the pages, which are its siblings.
            let noSize: UINT = 0x0001, noMove: UINT = 0x0002, noActivate: UINT = 0x0010
            _ = SetWindowPos(column, HWND(bitPattern: 0), 0, 0, 0, 0, noSize | noMove | noActivate)
        } else if dockedColumnWidth > 0 {
            if lastRegionSize != nil {
                _ = SetWindowRgn(column, nil, true)
                lastRegionSize = nil
            }
            let width = dockedColumnWidth
            try? bridge.moveAndResize(RectInt32(x: sidebarSide == .right ? frame.x + frame.width : 0, y: 0, width: width, height: height))
            _ = ShowWindow(column, SW_SHOWNA)
        } else {
            _ = ShowWindow(column, SW_HIDE)
        }
    }
}

/// An opaque colour for the window's own painting.
struct HostColor: Equatable {
    var r: UInt8, g: UInt8, b: UInt8

    /// GDI's COLORREF, 0x00BBGGRR.
    var colorRef: COLORREF { COLORREF(r) | COLORREF(g) << 8 | COLORREF(b) << 16 }

    /// This colour with `other` laid over it at `alpha`.
    func blended(with other: HostColor, alpha: Double) -> HostColor {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * (1 - alpha) + Double(b) * alpha).rounded()) }
        return HostColor(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b))
    }
}

/// The left button on the window's own client area (HostWindow.onMouse).
enum HostMouseEvent {
    case down(x: Int32, y: Int32, clicks: Int)
    case move(x: Int32, y: Int32)
    case up(x: Int32, y: Int32)
    /// The mouse capture was taken away before the release.
    case cancelled
}

/// System pointers, by their IDC_ resource numbers.
enum HostCursor: UInt {
    case resizeLeftRight = 32644  // IDC_SIZEWE
    case resizeUpDown = 32645  // IDC_SIZENS
    case hand = 32649  // IDC_HAND
}
