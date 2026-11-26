import CraCEFWin
import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

/// Arc's preview for a picture or video picked in Library ▸ Media (the Mac's MediaPreviewWindow;
/// CraCore `MediaPreview` has the measurements): a panel over the dimmed window, the Library and
/// the space left as they were. Its 46 DIP header holds ✕, ‹ ›, the file's name and age, then ⋯
/// (the tile's menu) and "Open in Photos ↗" (the file's own app). ✕, Esc, Space on a picture or
/// a click on the dimmed window closes it; ‹ › and the arrow keys step through the grid.
///
/// The page is a child window, over anything the browser window's XAML draws, so the dimming is
/// a veil of its own (CraOverlay, as the Peek's) and the panel a FloatingWindow over it.
@MainActor
final class MediaPreviewWin {
    /// The one on screen.
    private static var shown: MediaPreviewWin?

    private var files: [MediaLibrary.File]
    private var index: Int
    private let host: HostWindow
    private let store: SidebarStore
    private let onClose: () -> Void
    private var window: FloatingWindow?
    private var veil: UInt = 0
    private let box: Unmanaged<Box>
    private var closed = false
    /// Each picture asked for, so one that arrives after the next was asked for is dropped.
    private var generation = 0

    private let root = Grid()
    private let backdrop = WinUI.Image()
    private let picture = WinUI.Image()
    private let play = FontIcon()
    private var playButton: Button?
    private let name = TextBlock()
    private let age = TextBlock()
    private var back: Button?
    private var forward: Button?
    private var openLabel: TextBlock?
    private let menu = MenuFlyout()
    /// The controls' WinRT wrappers, kept (one only Swift held would go, and its handlers with it).
    private var kept: [AnyObject] = []

    private final class Box {
        weak var owner: MediaPreviewWin?
    }

    /// Shows `files[index]` over `host`; `onClose` runs once it has gone.
    static func show(_ files: [MediaLibrary.File], at index: Int, over host: HostWindow, store: SidebarStore,
                     onClose: @escaping () -> Void = {}) {
        guard files.indices.contains(index) else { return }
        shown?.close()
        let preview = MediaPreviewWin(files: files, index: index, host: host, store: store, onClose: onClose)
        guard preview.open() else { return }
        shown = preview
    }

    static var isShown: Bool { shown != nil }

    private init(files: [MediaLibrary.File], index: Int, host: HostWindow, store: SidebarStore, onClose: @escaping () -> Void) {
        self.files = files
        self.index = index
        self.host = host
        self.store = store
        self.onClose = onClose
        box = Unmanaged.passRetained(Box())
        box.takeUnretainedValue().owner = self
    }

    private func open() -> Bool {
        build()
        do {
            let window = try FloatingWindow(owner: host, content: root)
            window.onClose = { [weak self] in self?.close() }
            self.window = window
        } catch {
            print("Cra: the media preview's window could not be made: \(error)")
            box.release()
            return false
        }
        let clicked: CraOverlayClicked = { context in
            guard let context else { return }
            let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
            // After the click's own message: closing destroys the window it came to.
            _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { MainActor.assumeIsolated { box.owner?.close() } }
        }
        let alpha = Int32((MediaPreview.dim * 255).rounded())
        veil = cra_overlay_create(host.hwnd, 0x000000, alpha, box.toOpaque(), clicked)
        place()
        window?.show { [weak self] in _ = try? self?.root.focus(.programmatic) }
        // The veil just under the panel, once the panel is in front.
        placeVeil()
        showFile()
        return true
    }

    /// The panel where Arc's goes in the window's client area (CraCore's inset proportions, the
    /// same from either corner), the veil over all of it.
    private func place() {
        guard let window, let hwnd = HWND(bitPattern: host.hwnd) else { return }
        var origin = POINT(x: 0, y: 0)
        _ = ClientToScreen(hwnd, &origin)
        let size = host.appWindow.clientSize
        let panel = MediaPreview.panel(in: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)))
        window.place(origin: PointInt32(x: origin.x + Int32(panel.minX), y: origin.y + Int32(panel.minY)),
                     size: SizeInt32(width: Int32(panel.width), height: Int32(panel.height)))
    }

    private func placeVeil() {
        guard veil != 0, let window, let hwnd = HWND(bitPattern: host.hwnd) else { return }
        var origin = POINT(x: 0, y: 0)
        _ = ClientToScreen(hwnd, &origin)
        let size = host.appWindow.clientSize
        cra_overlay_place(veil, origin.x, origin.y, size.width, size.height, window.hwnd)
    }

    func close() {
        guard !closed else { return }
        closed = true
        if Self.shown === self { Self.shown = nil }
        cra_overlay_destroy(veil)
        veil = 0
        // After the click's event: the XAML that delivered it goes with the window.
        let window = self.window
        self.window = nil
        window?.hide()
        _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { window?.destroy() }
        box.release()
        host.activate()
        onClose()
    }

    // MARK: The panel

    private func build() {
        // Arc's panel: light grey under a white wash over a blurred copy of the picture; WinUI's
        // XAML has no blur, so the copy is faint and stretched to fill instead.
        root.background = UI.brush(209, 209, 209)
        root.requestedTheme = .dark
        root.isTabStop = true
        // Windows 11 rounds the panel's window (8 px) and gives it its shadow; Arc's 16 pt corner
        // would leave the window's own fill showing past it.
        for height in [UI.pixels(MediaPreview.headerHeight), UI.star] { root.rowDefinitions.append(UI.row(height)) }
        backdrop.stretch = .uniformToFill
        backdrop.opacity = 0.4
        root.children.append(backdrop)
        try? Grid.setRowSpan(backdrop, 2)
        let wash = Border()
        wash.background = UI.brush(255, 255, 255, alpha: 71)
        root.children.append(wash)
        try? Grid.setRowSpan(wash, 2)

        let header = Grid()
        header.background = UI.brush(46, 56, 66, alpha: 107)
        for width in [UI.auto, UI.auto, UI.auto, UI.star, UI.auto, UI.auto] { header.columnDefinitions.append(UI.column(width)) }
        header.padding = Thickness(left: 9, top: 0, right: 7, bottom: 0)
        let close = glyphButton("xmark", label: "Close") { [weak self] in self?.close() }
        let back = glyphButton("chevron.left", label: "Previous") { [weak self] in self?.step(-1) }
        let forward = glyphButton("chevron.right", label: "Next") { [weak self] in self?.step(1) }
        back.margin = Thickness(left: 6, top: 0, right: 0, bottom: 0)
        self.back = back
        self.forward = forward
        for (column, button) in [close, back, forward].enumerated() {
            header.children.append(button)
            try? Grid.setColumn(button, Int32(column))
        }
        let title = StackPanel()
        title.orientation = .horizontal
        title.spacing = 8
        title.verticalAlignment = .center
        title.margin = Thickness(left: 14, top: 0, right: 16, bottom: 0)
        name.fontSize = 13
        name.fontWeight = UWP.FontWeight(weight: 600)
        name.foreground = UI.brush(255, 255, 255, alpha: 235)
        name.textTrimming = .characterEllipsis
        age.fontSize = 13
        age.foreground = UI.brush(255, 255, 255, alpha: 140)
        title.children.append(name)
        title.children.append(age)
        header.children.append(title)
        try? Grid.setColumn(title, 3)

        // ⋯: the tile's own menu (Copy, Show in File Explorer, Hide).
        let more = filledButton(glyph: "ellipsis", title: nil, label: "More") {}
        more.flyout = menu
        more.margin = Thickness(left: 0, top: 0, right: 8, bottom: 0)
        header.children.append(more)
        try? Grid.setColumn(more, 4)
        let label = UI.text("Open", size: 13, color: UI.brush(255, 255, 255, alpha: 235))
        label.fontWeight = UWP.FontWeight(weight: 500)
        openLabel = label
        let openButton = filledButton(glyph: "arrow.up.right", title: label, label: "Open") { [weak self] in self?.openInApp() }
        header.children.append(openButton)
        try? Grid.setColumn(openButton, 5)
        root.children.append(header)

        let media = Grid()
        media.margin = Thickness(left: MediaPreview.mediaInset, top: MediaPreview.mediaInset,
                                 right: MediaPreview.mediaInset, bottom: MediaPreview.mediaInset)
        picture.stretch = .uniform
        media.children.append(picture)
        // A video shows its picture with Arc's ▶; a click plays it in its app (no player here yet).
        play.glyph = WinGlyph.code("play.fill")
        play.fontSize = 44
        play.foreground = UI.brush(255, 255, 255, alpha: 230)
        let playButton = UI.button(play, padding: Thickness(left: 20, top: 20, right: 20, bottom: 20)) { [weak self] in self?.openInApp() }
        playButton.background = UI.brush(0, 0, 0, alpha: 90)
        playButton.cornerRadius = CornerRadius(topLeft: 44, topRight: 44, bottomRight: 44, bottomLeft: 44)
        playButton.horizontalAlignment = .center
        playButton.verticalAlignment = .center
        try? AutomationProperties.setName(playButton, "Play")
        media.children.append(playButton)
        self.playButton = playButton
        root.children.append(media)
        try? Grid.setRow(media, 1)

        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            let key: MediaPreview.Key
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x1B: key = .escape
            case 0x25: key = .left
            case 0x27: key = .right
            case 0x20: key = .space
            default: return
            }
            guard let action = MediaPreview.action(for: key, isVideo: MediaLibrary.isVideo(self.files[self.index].path)) else { return }
            args.handled = true
            switch action {
            case .close: self.close()
            case .step(let delta): self.step(delta)
            }
        }
    }

    /// ✕ ‹ ›: a white glyph on nothing, Arc's hover fill under the pointer.
    private func glyphButton(_ symbol: String, label: String, _ action: @escaping @MainActor () -> Void) -> Button {
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code(symbol)
        glyph.fontSize = 14
        glyph.foreground = UI.brush(255, 255, 255, alpha: 230)
        let button = UI.button(glyph, padding: Thickness(left: 8, top: 8, right: 8, bottom: 8), action)
        button.background = UI.brush(0, 0, 0, alpha: 0)
        button.verticalAlignment = .center
        button.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        ArcTip.set(button, label)
        try? AutomationProperties.setName(button, label)
        kept.append(button)
        return button
    }

    /// ⋯ and Open in …: a translucent white fill, the title then the glyph.
    private func filledButton(glyph symbol: String, title: TextBlock?, label: String, _ action: @escaping @MainActor () -> Void) -> Button {
        let content = StackPanel()
        content.orientation = .horizontal
        content.spacing = 6
        if let title {
            title.verticalAlignment = .center
            content.children.append(title)
        }
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code(symbol)
        glyph.fontSize = title == nil ? 14 : 11
        glyph.foreground = UI.brush(255, 255, 255, alpha: 230)
        glyph.verticalAlignment = .center
        content.children.append(glyph)
        let button = UI.button(content, padding: Thickness(left: 10, top: 7, right: 10, bottom: 7), action)
        button.background = UI.brush(255, 255, 255, alpha: 46)
        button.verticalAlignment = .center
        button.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        try? AutomationProperties.setName(button, label)
        kept.append(button)
        return button
    }

    // MARK: The file

    private func showFile() {
        guard files.indices.contains(index) else { return }
        let file = files[index]
        name.text = file.name
        age.text = MediaPreview.age(file.date, now: Date())
        back?.isEnabled = index > 0
        forward?.isEnabled = index < files.count - 1
        back?.opacity = index > 0 ? 1 : 0.35
        forward?.opacity = index < files.count - 1 ? 1 : 0.35
        openLabel?.text = MediaPreview.openTitle(app: Self.appName(file.path))
        playButton?.visibility = MediaLibrary.isVideo(file.path) ? .visible : .collapsed
        buildMenu(file)
        // The picture at the panel's size, read off the UI thread; the grid's thumbnail meanwhile.
        picture.source = MediaScannerWin.shared.thumbnail(file)
        backdrop.source = picture.source
        generation += 1
        let asked = generation, path = file.path
        let side = Int32(max(host.appWindow.clientSize.width, host.appWindow.clientSize.height))
        guard let dispatcher = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil else { return }
        let queue = UncheckedSendable(value: dispatcher)
        let arrived: @MainActor (Pixels?) -> Void = { [weak self] pixels in
            guard let self, !self.closed, asked == self.generation, let image = pixels?.bitmap() else { return }
            self.picture.source = image
            self.backdrop.source = image
        }
        let done = UncheckedSendable(value: arrived)
        DispatchQueue.global(qos: .userInitiated).async {
            let pixels = Pixels.file(path, side: Int(min(max(side, 400), 2560)))
            _ = try? queue.value.tryEnqueue { onMain { done.value(pixels) } }
        }
    }

    private func buildMenu(_ file: MediaLibrary.File) {
        menu.items.clear()
        let video = MediaLibrary.isVideo(file.path)
        for (i, action) in MediaLibrary.windowsActions.enumerated() {
            if action.startsGroup, i > 0 { menu.items.append(MenuFlyoutSeparator()) }
            menu.items.append(UI.menuItem(action.windowsTitle(isVideo: video)) { [weak self] in
                guard let self else { return }
                switch action {
                case .copy: MediaClipboard.copy(file.path)
                case .showInFinder: Shell.showInFolder(file.path)
                case .hide: self.hide(file)
                case .sendMessage, .airDrop: break
                }
            })
        }
    }

    /// Hidden from the grid; the next one shows, or the preview closes with nothing left.
    private func hide(_ file: MediaLibrary.File) {
        if !store.settings.mediaHidden.contains(file.path) { store.settings.mediaHidden.append(file.path) }
        guard let rest = MediaPreview.hiding(index, from: files) else { return close() }
        files = rest.files
        index = rest.index
        showFile()
    }

    private func step(_ delta: Int) {
        guard let next = MediaPreview.step(index, by: delta, count: files.count) else { return }
        index = next
        showFile()
    }

    private func openInApp() {
        Shell.open(files[index].path)
        close()
    }

    /// The name Windows gives the file's app ("Photos"), nil when it names none.
    private static func appName(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 512)
        guard cra_shell_default_app_name(path, &buffer, buffer.count) != 0 else { return nil }
        return String(cString: buffer)
    }
}
