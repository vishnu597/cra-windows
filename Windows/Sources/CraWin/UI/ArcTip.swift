import CraCEFWin
import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

/// Arc's hover tips (the Mac's ArcTooltipController) in place of WinUI's: the pointer rests
/// 1.6 s on a control (none when moving on from another tip), then a capsule in the window's
/// space tones hangs off its bottom-trailing corner, with its shortcut in key caps; a click hides
/// it. CraCore's ArcTooltipRules decides; CraTooltip.cpp draws.
@MainActor
enum ArcTip {
    /// The tones of the browser window whose top-level window is `hwnd` (WindowList sets it);
    /// nil, or another window, takes Little Arc's navy.
    static var tones: (UInt) -> TooltipTones? = { _ in nil }

    /// `help` ("Copy URL (Ctrl+Shift+C)") as `element`'s tip, replacing any it had; an empty
    /// help leaves it without one. The help is kept as the element's UI Automation help text
    /// (what a screen reader says for a Mac tip too), so nothing in Swift has to outlive the
    /// element's wrapper, and the handlers go on the first time only.
    /// `badge` is a space icon's profile, shown in a pill after the text (kept as the element's
    /// UI Automation item status, so a screen reader says it too).
    static func set(_ element: UIElement, _ help: String, placement: ArcTooltipRules.Placement = .corner, badge: String? = nil) {
        let old = (try? AutomationProperties.getHelpText(element)) ?? ""
        try? AutomationProperties.setHelpText(element, help)
        try? AutomationProperties.setItemStatus(element, badge ?? "")
        if !old.isEmpty {
            // Its tip on screen follows (Refresh turning into Stop).
            if let hovered, hovered.shown, hovered.help == old, old != help { help.isEmpty ? hide() : show(update: help) }
            return
        }
        guard !help.isEmpty else { return }
        // The sender, not `element`: an element holding itself in its handlers would never go.
        element.pointerEntered.addHandler { sender, args in
            guard let args, let element = sender as? UIElement else { return }
            pointer(in: element, args, placement: placement)
        }
        element.pointerMoved.addHandler { sender, args in
            guard let args, let element = sender as? UIElement else { return }
            pointer(in: element, args, placement: placement)
        }
        element.pointerExited.addHandler { _, _ in exited() }
        element.pointerCanceled.addHandler { _, _ in exited() }
        element.pointerCaptureLost.addHandler { _, _ in exited() }
        element.pointerPressed.addHandler { _, _ in dismiss() }
    }

    /// A click or a key: the tip goes, and the next one waits the whole delay again.
    static func dismiss() {
        cancelPending()
        hide()
        lastHiddenAt = nil
    }

    // MARK: State

    /// The control under the pointer: its help, the control's centre and the pointer on
    /// screen (physical pixels), its scale and placement, and whether its tip shows.
    private struct Hovered {
        var help: String
        var badge: String?
        var placement: ArcTooltipRules.Placement
        var centre: POINT
        var pointer: POINT
        var scale: Double
        var shown = false
    }

    private static var hovered: Hovered?
    private static var timer: WinAppSDK.DispatcherQueueTimer?
    private static var pendingHelp: String?
    private static var lastHiddenAt: Double?
    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    private static func pointer(in element: UIElement, _ args: PointerRoutedEventArgs, placement: ArcTooltipRules.Placement) {
        let help = (try? AutomationProperties.getHelpText(element)) ?? ""
        let status = (try? AutomationProperties.getItemStatus(element)) ?? ""
        let badge: String? = status.isEmpty ? nil : status
        guard !help.isEmpty, let frame = element as? FrameworkElement, let point = try? args.getCurrentPoint(element) else { return }
        let position = point.position
        var cursor = POINT(x: 0, y: 0)
        _ = GetCursorPos(&cursor)
        let scale = element.xamlRoot.map { $0.rasterizationScale } ?? 1
        // The control's centre on screen: from the pointer back to the control's corner, then half of it.
        let cx = Double(cursor.x) + (frame.actualWidth / 2 - Double(position.x)) * scale
        let cy = Double(cursor.y) + (frame.actualHeight / 2 - Double(position.y)) * scale
        let centre = POINT(x: Int32(cx.rounded()), y: Int32(cy.rounded()))
        let same = hovered.map { $0.help == help && $0.centre.x == centre.x && $0.centre.y == centre.y } ?? false
        let anyShown = tipShowing
        if same, anyShown {
            hovered = Hovered(help: help, badge: badge, placement: placement, centre: centre, pointer: cursor, scale: scale, shown: true)
            return
        }
        // Onto another control with a tip still up (a child inside its parent): that tip goes now,
        // and this one follows at once.
        if anyShown { hide() }
        hovered = Hovered(help: help, badge: badge, placement: placement, centre: centre, pointer: cursor, scale: scale)
        // On mouse idle: every move restarts the wait.
        let wait = ArcTooltipRules.delay(tipShowing: anyShown, lastHiddenAt: lastHiddenAt, now: now,
                                         idleDelay: ArcTooltipRules.idleDelay(for: placement))
        guard wait > 0 else { return show() }
        pendingHelp = help
        try? timer?.stop()
        if timer == nil, let queue = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil {
            timer = try? queue.createTimer()
            timer?.isRepeating = false
            timer?.tick.addHandler { _, _ in
                guard pendingHelp != nil, pendingHelp == hovered?.help else { return }
                pendingHelp = nil
                show()
            }
        }
        timer?.interval = TimeSpan(duration: Int64(wait * 10_000_000))
        try? timer?.start()
    }

    private static var tipShowing: Bool { hovered?.shown == true }

    private static func exited() {
        cancelPending()
        hide()
        hovered = nil
    }

    private static func cancelPending() {
        try? timer?.stop()
        pendingHelp = nil
    }

    private static func hide() {
        guard hovered?.shown == true else { return }
        hovered?.shown = false
        lastHiddenAt = now
        cra_arc_tip_hide()
    }

    /// The hovered control's help changed while its tip shows (Refresh turning into Stop).
    private static func show(update help: String) {
        hovered?.help = help
        show()
    }

    // MARK: Drawing

    private static func show() {
        cancelPending()
        guard let target = hovered else { return }
        let (text, keys) = ArcTooltipRules.split(target.help)
        guard !text.isEmpty else { return }
        let M = ArcTooltipRules.Metrics.self
        var textWidth = 0.0, textHeight = 0.0
        var glyphWidths = [Double](repeating: 0, count: keys.count)
        withCStrings(keys) { keyPointers in
            text.withCString { t in
                glyphWidths.withUnsafeMutableBufferPointer { widths in
                    cra_arc_tip_measure(t, M.maxTextWidth, keyPointers, keys.count, &textWidth, &textHeight, widths.baseAddress)
                }
            }
        }
        textWidth = textWidth.rounded(.up)
        textHeight = textHeight.rounded(.up)
        let capWidths = zip(glyphWidths, keys).map { M.capWidth(glyphWidth: $0, characters: $1.count) }
        let badge = target.badge
        let pillWidth = badge.map { name in name.withCString { M.pillWidth(nameWidth: cra_arc_tip_measure_badge($0)) } }
        let size = M.size(textWidth: textWidth, textHeight: textHeight, capWidths: capWidths, pillWidth: pillWidth)
        // A wrapped tip has no pill (the size left it out).
        let showsPill = pillWidth != nil && size.height <= M.height
        let scale = target.scale
        // In DIPs for the rules, then back to pixels.
        let screen = workArea(at: target.pointer)
        let origin = ArcTooltipRules.origin(
            placement: target.placement,
            centre: (Double(target.centre.x) / scale, Double(target.centre.y) / scale),
            pointer: (Double(target.pointer.x) / scale, Double(target.pointer.y) / scale),
            size: size,
            screen: (Double(screen.left) / scale, Double(screen.top) / scale,
                     Double(screen.right - screen.left) / scale, Double(screen.bottom - screen.top) / scale))
        var root = HWND(bitPattern: 0)
        if let under = WindowFromPoint(target.pointer) { root = GetAncestor(under, UINT(GA_ROOT)) }
        let colors = tones(UInt(bitPattern: root)).map(ArcTooltipRules.Colors.init) ?? .little
        var native = CraArcTipColors(fill: hex(colors.fill), title: hex(colors.title), cap: hex(colors.cap),
                                     cap_glyph: hex(colors.capGlyph), cap_edge: hex(colors.capEdge), ring: hex(colors.ring))
        let shownText = min(textWidth, M.maxTextWidth)
        let pillName = showsPill ? (badge ?? "") : ""
        let pillX = M.pillX(textWidth: textWidth)
        withCStrings(keys) { keyPointers in
            text.withCString { t in
                pillName.withCString { b in
                    capWidths.withUnsafeBufferPointer { widths in
                        cra_arc_tip_show(Int32((origin.x * scale).rounded()), Int32((origin.y * scale).rounded()), size.width, size.height,
                                         scale, M.cornerRadius(height: size.height), t, shownText, keyPointers, widths.baseAddress,
                                         keys.count, b, pillX, showsPill ? (pillWidth ?? 0) : 0, &native)
                    }
                }
            }
        }
        hovered?.shown = true
    }

    private static func hex(_ c: RGB) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(c.r) << 16 | byte(c.g) << 8 | byte(c.b)
    }

    private static func workArea(at point: POINT) -> RECT {
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        if let monitor = MonitorFromPoint(point, DWORD(MONITOR_DEFAULTTONEAREST)), GetMonitorInfoW(monitor, &info) { return info.rcWork }
        return RECT(left: 0, top: 0, right: 1920, bottom: 1080)
    }

    /// `strings` as C strings for the length of `body`.
    private static func withCStrings(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> Void) {
        let copies: [UnsafeMutablePointer<CChar>] = strings.map { text in
            let utf8 = text.utf8CString
            let copy = UnsafeMutablePointer<CChar>.allocate(capacity: utf8.count)
            for (i, c) in utf8.enumerated() { copy[i] = c }
            return copy
        }
        defer { copies.forEach { $0.deallocate() } }
        let pointers: [UnsafePointer<CChar>?] = copies.map { UnsafePointer($0) }
        pointers.withUnsafeBufferPointer { body($0.baseAddress) }
    }
}
