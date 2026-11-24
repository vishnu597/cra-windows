import CraCore
import Foundation
import UWP
import WinSDK
import WinUI

/// Arc's toolbar over the page (View ▸ Show Toolbar, the Mac's PaneToolbarView with kind `.normal`
/// or `.noTab`): the sidebar toggle while the sidebar is hidden, ← → and ↻ (an ✕ while the page
/// loads), the site's address centred (the whole URL with Show Full URL), then the Site Control
/// Center's sliders and Split View, in the page's colour (white until the tab has one). CraCore's
/// ToolbarComposition picks the buttons, ToolbarAddress the text and PeekLayout.BarColors the
/// colours, as on the Mac. HostWindow shows it in its strip over the page.
@MainActor
final class ToolbarView {
    /// Arc's toolbar is 32 pt (CraMetrics.toolbarHeight).
    static let height = 32.0

    /// An action by its id, as the command bar runs them: "toggleSidebar", "goBack", "goForward",
    /// "reload", "stop", "editURL", "copyURL", "addSplitView", "toggleToolbar"; "siteControls" for
    /// the sliders and "toggleFullURL" for the address menu's Show Full URL.
    var onAction: (String) -> Void = { _ in }
    /// A key the bar doesn't use itself (it has the keyboard after a click): Cra's shortcuts.
    var onKey: (KeyPress) -> Bool = { _ in false }
    /// The window's history menus (right-click ← or →, BackForwardMenu) and reload menu (right-click
    /// ↻, ReloadMenuItems), shared with the sidebar header's buttons.
    var menus: (back: MenuFlyout, forward: MenuFlyout, reload: MenuFlyout)?

    struct State: Equatable {
        var kind: ToolbarComposition.Kind = .noTab
        var url = ""
        var easelTitle: String?
        var themeColor: String?
        var canGoBack = false, canGoForward = false, isLoading = false
        var sidebarVisible = true
        var sidebarSide: SidebarSide = .left
        var showFullURL = false
        var autoHide = false
        /// The page's profile's pinned extensions that can run, in toolbar order.
        var pins: [Pin] = []
    }

    /// A pinned extension's button: its name (the tooltip) and its button icon.
    struct Pin: Equatable {
        let id: String
        let name: String
        let icon: WriteableBitmap?

        static func == (a: Pin, b: Pin) -> Bool { a.id == b.id && a.name == b.name && a.icon === b.icon }
    }

    /// A pin's click: onAction with this before the extension's id.
    static let pinAction = "runExtension:"

    let root = Grid()
    /// The Site Control Center's sliders, which it and an extension's popup hang from.
    private(set) var sliders: Button?
    /// The pinned extensions' buttons by extension id, which their popups hang from.
    private(set) var pinButtons: [String: Button] = [:]
    private let left = StackPanel()
    private let right = StackPanel()
    private var address: Button!
    private let host = TextBlock()
    private let path = TextBlock()
    private let hairline = Border()
    private var shown: State?
    /// The address's menu, kept: a MenuFlyout made from Swift is only a wrapper, freed with its last
    /// Swift reference.
    private var menu: MenuFlyout?

    init() {
        build()
        show(State())
    }

    func show(_ state: State) {
        guard state != shown else { return }
        shown = state
        let colors = PeekLayout.BarColors(reported: state.themeColor)
        let ink = brush(colors.ink, alpha: colors.inkAlpha), dim = brush(colors.dimInk, alpha: colors.dimInkAlpha)
        // On a white bar white at 10 % shows nothing: a dark wash instead (Arc's hover reads on both).
        let hot = colors.light ? UI.brush(0, 0, 0, alpha: 20) : UI.brush(255, 255, 255, alpha: UInt8((PeekLayout.BarColors.hoverAlpha * 255).rounded()))
        root.background = brush(colors.fill)
        root.requestedTheme = colors.light ? .light : .dark
        hairline.background = colors.light ? UI.brush(0, 0, 0, alpha: 18) : UI.brush(255, 255, 255, alpha: 18)

        let bar = ToolbarComposition(kind: state.kind, inSplit: false, sidebarVisible: state.sidebarVisible, sidebarSide: state.sidebarSide,
                                     focusedPane: true, canGoBack: state.canGoBack, canGoForward: state.canGoForward,
                                     isLoading: state.isLoading, pinnedExtensions: state.pins.map(\.id))
        left.children.clear()
        right.children.clear()
        sliders = nil
        pinButtons = [:]
        for item in bar.left { if let b = button(item, dim: dim, hot: hot) { left.children.append(b) } }
        for item in bar.right { if let b = button(item, dim: dim, hot: hot) { right.children.append(b) } }
        // The address stays centred, clear of the longer side (four buttons at least, as on the
        // Mac; more with pinned extensions).
        let side = 37.0 * Double(max(4, left.children.count, right.children.count)) + 8
        address.margin = Thickness(left: side, top: 0, right: side, bottom: 0)

        let parts = ToolbarAddress.parts(url: state.url, showFullURL: state.showFullURL, easelTitle: state.easelTitle)
        host.text = parts.host
        host.foreground = ink
        path.text = parts.path
        path.foreground = dim
        address.visibility = state.url.isEmpty ? .collapsed : .visible
        paint(address, hover: colors.light ? UI.brush(0, 0, 0, alpha: 14) : UI.brush(255, 255, 255, alpha: 20), ink: ink)
        ArcTip.set(address, state.url)
        let menu = addressMenu(showFullURL: state.showFullURL, autoHide: state.autoHide)
        self.menu = menu
        address.contextFlyout = menu
    }

    /// The keyboard in the bar, for its key handler to hear (HostWindow.focusTopBar first).
    func takeKeyboard() {
        _ = try? address.focus(.programmatic)
    }

    // MARK: Layout

    private func build() {
        root.height = Self.height
        for part in [left, right] {
            part.orientation = .horizontal
            part.verticalAlignment = .center
        }
        left.horizontalAlignment = .left
        left.margin = Thickness(left: 2.5, top: 0, right: 0, bottom: 0)
        right.horizontalAlignment = .right
        right.margin = Thickness(left: 0, top: 0, right: 2.5, bottom: 0)

        let label = StackPanel()
        label.orientation = .horizontal
        label.verticalAlignment = .center
        host.fontSize = 13
        host.fontWeight = UWP.FontWeight(weight: 500)
        host.verticalAlignment = .center
        label.children.append(host)
        path.fontSize = 13
        path.verticalAlignment = .center
        path.textTrimming = .characterEllipsis
        label.children.append(path)
        address = UI.button(label, padding: Thickness(left: 8, top: 0, right: 8, bottom: 0)) { [weak self] in self?.onAction("editURL") }
        address.height = 26
        address.horizontalAlignment = .center
        address.verticalAlignment = .center
        // Clear of four buttons on either side (4 × 37 + 2.5, and a little more), as on the Mac.
        address.margin = Thickness(left: 156, top: 0, right: 156, bottom: 0)
        try? AutomationProperties.setName(address, "Address")

        hairline.height = 1
        hairline.verticalAlignment = .bottom
        hairline.isHitTestVisible = false

        for part in [left, address!, right, hairline] as [FrameworkElement] { root.children.append(part) }

        // Cra's shortcuts while the bar has the keyboard (the page reports its own).
        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, !args.handled else { return }
            let key = KeyPress(keyCode: Int32(truncatingIfNeeded: args.key.rawValue), control: GetKeyState(0x11) < 0,
                               shift: GetKeyState(0x10) < 0, alt: GetKeyState(0x12) < 0)
            if self.onKey(key) { args.handled = true }
        }
    }

    /// One of ToolbarComposition's items as a 37 × 26 glyph button; nil for what the Windows bar
    /// doesn't carry yet.
    private func button(_ item: ToolbarComposition.Item, dim: Brush, hot: Brush) -> Button? {
        let symbol: String, name: String, action: String, enabled: Bool
        switch item {
        case .toggleSidebar:
            (symbol, name, action, enabled) = ("sidebar.left", "Toggle Sidebar", "toggleSidebar", true)
        case .back(let on): (symbol, name, action, enabled) = ("arrow.left", "Go Back", "goBack", on)
        case .forward(let on): (symbol, name, action, enabled) = ("arrow.right", "Go Forward", "goForward", on)
        case .reload(let loading, let on):
            (symbol, name, action, enabled) = loading ? ("xmark", "Stop", "stop", on) : ("arrow.clockwise", "Refresh", "reload", on)
        case .extensions: (symbol, name, action, enabled) = ("slider.horizontal.3", "Site Controls", "siteControls", true)
        case .addSplit: (symbol, name, action, enabled) = ("square.split.2x1", "Add Split View", "addSplitView", shown?.kind == .normal)
        case .pinnedExtension(let id):
            return shown?.pins.first { $0.id == id }.map { pinButton($0, dim: dim, hot: hot) }
        default: return nil
        }
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code(symbol)
        glyph.fontSize = 15
        glyph.foreground = dim
        // Never disabled, which WinUI draws as a grey block: a dimmer glyph says it does nothing now.
        glyph.opacity = enabled ? 1 : 0.4
        let b = UI.button(glyph, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
            if enabled { self?.onAction(action) }
        }
        b.width = 37
        b.height = 26
        paint(b, hover: hot, ink: dim)
        let keys = WinKeyBindings.shared.action(action)?.primary.map { " (\($0.windowsDisplay))" } ?? ""
        ArcTip.set(b, name + keys)
        try? AutomationProperties.setName(b, name)
        if action == "siteControls" { sliders = b }
        switch item {
        case .back: b.contextFlyout = menus?.back
        case .forward: b.contextFlyout = menus?.forward
        case .reload(_, true): b.contextFlyout = menus?.reload
        default: break
        }
        return b
    }

    /// A pinned extension, its 16 DIP icon (else the puzzle piece) on a 37 × 26 button: a click
    /// runs it as its Site Control Center tile does.
    private func pinButton(_ pin: Pin, dim: Brush, hot: Brush) -> Button {
        let content: UIElement
        if let icon = pin.icon {
            content = UI.image(icon, size: 16)
        } else {
            let piece = FontIcon()
            piece.glyph = WinGlyph.code("puzzlepiece.extension")
            piece.fontSize = 14
            piece.foreground = dim
            content = piece
        }
        let action = Self.pinAction + pin.id
        let b = UI.button(content, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in self?.onAction(action) }
        b.width = 37
        b.height = 26
        paint(b, hover: hot, ink: dim)
        ArcTip.set(b, pin.name)
        try? AutomationProperties.setName(b, pin.name)
        pinButtons[pin.id] = b
        return b
    }

    /// Arc's address menu: Copy URL, Show Full URL or Hide Full URL, Hide Toolbar.
    private func addressMenu(showFullURL: Bool, autoHide: Bool) -> MenuFlyout {
        let menu = MenuFlyout()
        func item(_ title: String, _ action: String) {
            let entry = MenuFlyoutItem()
            entry.text = title
            entry.click.addHandler { [weak self] _, _ in self?.onAction(action) }
            menu.items.append(entry)
        }
        item("Copy URL", "copyURL")
        menu.items.append(MenuFlyoutSeparator())
        item(showFullURL ? "Hide Full URL" : "Show Full URL", "toggleFullURL")
        let hides = ToggleMenuFlyoutItem()
        hides.text = "Automatically Hide Toolbar"
        hides.isChecked = autoHide
        hides.click.addHandler { [weak self] _, _ in self?.onAction("toggleAutoHideToolbar") }
        menu.items.append(hides)
        item("Hide Toolbar", "toggleToolbar")
        return menu
    }

    /// The hover and press fill, keeping the content's own colour (WinUI's default turns it white).
    private func paint(_ b: Button, hover: Brush, ink: Brush) {
        for key in ["ButtonBackgroundPointerOver", "ButtonBackgroundPressed"] { _ = b.resources.insert(key, hover) }
        for key in ["ButtonForegroundPointerOver", "ButtonForegroundPressed"] { _ = b.resources.insert(key, ink) }
    }

    private func brush(_ c: RGB, alpha: Double = 1) -> SolidColorBrush {
        UI.brush(UInt8((c.r * 255).rounded()), UInt8((c.g * 255).rounded()), UInt8((c.b * 255).rounded()),
                 alpha: UInt8((alpha * 255).rounded()))
    }
}
