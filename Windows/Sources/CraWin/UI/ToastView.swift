import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WindowsFoundation
import WinUI

/// Arc's toast (the Mac's ShinyToast): a short confirmation at the top right of the page,
/// "Copied Current URL" or "Screenshot Copied to Clipboard" with a Save button, in the space's
/// colours (CraCore's ToastStyle). It floats in a window of its own that never takes the
/// keyboard, and goes 4.85 s after the last message, or once the pointer leaves it. One shown
/// with `onClose` (the slow-response notice) stays until its ✕ is pressed or it is hidden.
@MainActor
final class ToastView {
    struct Action {
        let title: String
        let run: @MainActor () -> Void
    }

    private let root = Border()
    /// Chromium's classic scrollbar on Windows, in DIPs.
    private static let scrollbar = 15.0

    private let label = TextBlock()
    private let buttonLabel = TextBlock()
    private var button: Button!
    private var closeButton: Button!
    private let closeGlyph = FontIcon()
    private var action: Action?
    /// The ✕'s: set while the toast stays until it is closed.
    private var onClose: (() -> Void)?
    /// What is up, to place again when the window moves.
    private var shown: (text: String, theme: SpaceTheme)?
    private var window: FloatingWindow?
    private var timer: WinAppSDK.DispatcherQueueTimer?
    /// The page's frame on screen in physical pixels, and the scale: where the toast goes.
    private let page: () -> (left: Int32, top: Int32, right: Int32, scale: Double)?
    /// The window the toast belongs to, which takes the front back when the button is pressed.
    private let owner: UInt

    init(owner: HostWindow, page: @escaping () -> (left: Int32, top: Int32, right: Int32, scale: Double)?) {
        self.page = page
        self.owner = owner.hwnd
        build()
        do {
            window = try FloatingWindow(owner: owner, content: root)
            window?.onClose = { [weak self] in
                // Alt+F4 on it: as its ✕.
                let closed = self?.onClose
                self?.hide()
                closed?()
            }
        } catch {
            print("The toast's window could not be made: \(error)")
        }
    }

    var isShown: Bool { window?.isVisible == true }
    /// Up until its ✕ (or `hide`).
    var isPersistent: Bool { isShown && onClose != nil }

    /// `onClose`: the toast stays up, with a ✕ that hides it and calls this.
    func show(_ text: String, action: Action? = nil, theme: SpaceTheme, onClose: (() -> Void)? = nil) {
        guard let window, let page = page() else { return }
        self.action = action
        self.onClose = onClose
        shown = (text, theme)
        let colors = ToastStyle.colors(theme)
        func brush(_ c: RGB, alpha: UInt8 = 255) -> SolidColorBrush {
            UI.brush(UInt8((c.r * 255).rounded()), UInt8((c.g * 255).rounded()), UInt8((c.b * 255).rounded()), alpha: alpha)
        }
        // The Mac's vertical gradient, as its middle.
        root.background = brush(colors.top.mixed(with: colors.bottom, 0.5))
        root.borderBrush = brush(colors.outline)
        label.text = text
        label.foreground = brush(colors.text)
        buttonLabel.foreground = brush(colors.text)
        button.background = brush(colors.text, alpha: 40)
        _ = button.resources.insert("ButtonBackgroundPointerOver", brush(colors.text, alpha: 60))
        _ = button.resources.insert("ButtonBackgroundPressed", brush(colors.text, alpha: 80))
        buttonLabel.text = action?.title ?? ""
        button.visibility = action == nil ? .collapsed : .visible
        closeGlyph.foreground = brush(colors.text)
        _ = closeButton.resources.insert("ButtonBackgroundPointerOver", brush(colors.text, alpha: 30))
        _ = closeButton.resources.insert("ButtonBackgroundPressed", brush(colors.text, alpha: 50))
        closeButton.visibility = onClose == nil ? .collapsed : .visible

        // Its text's width decides its own: 12 either side, then the button and 8 around it.
        let infinite = WindowsFoundation.Size(width: .infinity, height: .infinity)
        try? label.measure(infinite)
        var width = Double(label.desiredSize.width).rounded(.up) + 2 * Double(ToastStyle.padding)
        if action != nil {
            try? button.measure(infinite)
            // Its desired size has the gap before it (its margin).
            width += Double(button.desiredSize.width).rounded(.up)
                - Double(ToastStyle.padding) + Double(ToastStyle.height - ToastStyle.buttonHeight) / 2
        }
        if onClose != nil {
            // The ✕ ends the row as the button does: (42 - 26) / 2 from the edge.
            if action == nil { width += Double(ToastStyle.height - ToastStyle.closeSize) / 2 - Double(ToastStyle.padding) }
            width += Double(ToastStyle.closeGap) + Double(ToastStyle.closeSize)
        }
        let scale = page.scale
        let w = Int32((width * scale).rounded()), h = Int32((Double(ToastStyle.height) * scale).rounded())
        // Clear of Chromium's scrollbar, which on Windows takes room at the page's edge (the
        // Mac's overlays it).
        let inset = Double(ToastStyle.trailingInset) + Self.scrollbar
        let x = page.right - Int32((inset * scale).rounded()) - w
        let y = page.top + Int32((Double(ToastStyle.topInset) * scale).rounded())
        window.place(origin: PointInt32(x: max(page.left, x), y: y), size: SizeInt32(width: w, height: h))
        window.showInactive()
        if onClose == nil {
            restartTimer()
        } else {
            try? timer?.stop()
            timer = nil
        }
    }

    /// Without calling `onClose`: whoever hides it knows.
    func hide() {
        try? timer?.stop()
        timer = nil
        action = nil
        onClose = nil
        shown = nil
        window?.hide()
    }

    /// The window moved: a toast that stays goes along, a passing one goes.
    func ownerMoved() {
        guard let shown, isPersistent else { return hide() }
        show(shown.text, action: action, theme: shown.theme, onClose: onClose)
    }

    private func restartTimer(after seconds: TimeInterval = ToastStyle.visibleFor) {
        try? timer?.stop()
        timer = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.createTimer()
        timer?.interval = TimeSpan(duration: Int64(seconds * 10_000_000))
        timer?.isRepeating = false
        // A pointer on its way to the button keeps it up.
        timer?.tick.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.window?.hasPointer == true { self.restartTimer(after: 1) } else { self.hide() }
        }
        try? timer?.start()
    }

    private func build() {
        root.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        root.cornerRadius = CornerRadius(topLeft: Double(ToastStyle.cornerRadius), topRight: Double(ToastStyle.cornerRadius),
                                         bottomRight: Double(ToastStyle.cornerRadius), bottomLeft: Double(ToastStyle.cornerRadius))
        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 0
        row.verticalAlignment = .center
        row.horizontalAlignment = .center
        label.fontSize = Double(ToastStyle.fontSize)
        label.fontWeight = UWP.FontWeight(weight: 500)
        label.verticalAlignment = .center
        row.children.append(label)
        buttonLabel.fontSize = Double(ToastStyle.buttonFontSize)
        buttonLabel.fontWeight = UWP.FontWeight(weight: 600)
        button = UI.button(buttonLabel, padding: Thickness(left: Double(ToastStyle.buttonPadding), top: 0,
                                                           right: Double(ToastStyle.buttonPadding), bottom: 0)) { [weak self] in
            guard let self, let action = self.action else { return }
            // The click made the toast the active window; hidden, Windows would hand the front to
            // whatever app is next, and Share opens nothing over a window that isn't in front
            // (PR #36's PC test). Its own window takes the front first.
            if let owner = HWND(bitPattern: self.owner) { _ = SetForegroundWindow(owner) }
            // One that stays keeps standing through its button: only the ✕ closes it (the Mac's ShinyToast).
            if self.onClose == nil { self.hide() }
            action.run()
        }
        button.margin = Thickness(left: Double(ToastStyle.buttonGap), top: 0, right: 0, bottom: 0)
        let capsule = Double(ToastStyle.buttonHeight) / 2
        button.height = Double(ToastStyle.buttonHeight)
        button.cornerRadius = CornerRadius(topLeft: capsule, topRight: capsule, bottomRight: capsule, bottomLeft: capsule)
        button.verticalAlignment = .center
        row.children.append(button)
        closeGlyph.glyph = WinGlyph.code("xmark")
        closeGlyph.fontSize = 11
        closeButton = UI.button(closeGlyph, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
            guard let self else { return }
            if let owner = HWND(bitPattern: self.owner) { _ = SetForegroundWindow(owner) }
            let closed = self.onClose
            self.hide()
            closed?()
        }
        let round = Double(ToastStyle.closeSize) / 2
        closeButton.width = Double(ToastStyle.closeSize)
        closeButton.height = Double(ToastStyle.closeSize)
        closeButton.cornerRadius = CornerRadius(topLeft: round, topRight: round, bottomRight: round, bottomLeft: round)
        closeButton.margin = Thickness(left: Double(ToastStyle.closeGap), top: 0, right: 0, bottom: 0)
        closeButton.verticalAlignment = .center
        closeButton.visibility = .collapsed
        try? ToolTipService.setToolTip(closeButton, "Close")
        try? AutomationProperties.setName(closeButton, "Close")
        row.children.append(closeButton)
        root.child = row
    }
}
