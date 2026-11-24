import CraCore
import Foundation
import UWP
import WinAppSDK
import WinSDK
import WindowsFoundation
import WinUI

/// Arc's tab switcher on Ctrl+Tab (the Mac's TabSwitcher and TabSwitcherView): the space's five
/// most recent tabs as cards over the middle of the window. While Ctrl is held, Ctrl+Tab /
/// Ctrl+Shift+Tab and the arrows move round, the pointer picks the card it moves over; letting
/// go of Ctrl, Return or a click switches, Escape or a click elsewhere cancels. A quick tap
/// switches to the previous tab without showing it. CraCore's TabSwitcherCycle decides.
///
/// Its window never takes the keyboard: the page or sidebar keeps it and hands each key here
/// (`handle`), and a timer looks for Ctrl being let go, as the Mac's flagsChanged does.
@MainActor
final class TabSwitcherWindow {
    struct Card {
        let id: UUID
        let title: String
        let iconKey: String?
        /// A split's panes (#554), in pane order with their share of its width; empty for a tab.
        var panes: [(iconKey: String?, width: Double)] = []
        /// Ctrl+Alt+Tab's cards (#467) name their space over the picture's corner.
        var spaceTitle: String?
    }

    private typealias L = TabSwitcherLayout
    private(set) var state = TabSwitcherCycle()
    var isOpen: Bool { state.isOpen }
    /// The card chosen: the window switches to its tab.
    var onCommit: (UUID) -> Void = { _ in }

    private let root = Border()
    private let row = StackPanel()
    private var cardViews: [Border] = []
    private var cards: [Card] = []
    private var window: FloatingWindow?
    private let ownerHwnd: UInt
    /// The owner's frame on screen (physical pixels) and its scale, to centre the panel on.
    private let frame: () -> (x: Int32, y: Int32, width: Int32, height: Int32, scale: Double)?
    private var timer: WinAppSDK.DispatcherQueueTimer?
    private var openedAt: UInt64 = 0
    private var shown = false
    private var dark = true
    private var highlight: SolidColorBrush?
    /// A panel that opens under a resting pointer keeps its keyboard selection until it moves.
    private var pointerAtShow: POINT?
    private var buttonWasDown = false

    init(owner: HostWindow, frame: @escaping () -> (x: Int32, y: Int32, width: Int32, height: Int32, scale: Double)?) {
        ownerHwnd = owner.hwnd
        self.frame = frame
        row.orientation = .horizontal
        row.spacing = Double(L.cardSpacing)
        root.padding = Thickness(left: Double(L.paddingH), top: Double(L.paddingV), right: Double(L.paddingH), bottom: Double(L.paddingV))
        root.child = row
        do {
            window = try FloatingWindow(owner: owner, content: root)
            window?.onClose = { [weak self] in self?.finish(commit: false) }
        } catch {
            print("The tab switcher's window could not be made: \(error)")
        }
    }

    /// The switcher's shortcut: the first press opens it on the next (or last) card, later ones
    /// move. Without Ctrl held (the command bar, a menu) it switches straight away.
    func cycle(_ delta: Int, theme: SpaceTheme, dark: Bool, cards make: () -> [Card]) {
        if state.isOpen {
            state.move(delta)
            redraw()
            return
        }
        let list = make()
        guard state.open(list.map(\.id), delta: delta) else { return }
        cards = list
        guard Self.controlHeld else { return finish(commit: true) }
        self.dark = dark
        let c = theme.switcherHighlightRGBA(dark: dark)
        highlight = UI.brush(Self.byte(c.r), Self.byte(c.g), Self.byte(c.b), alpha: Self.byte(c.a))
        // Arc: #1C1B1A inside a near-black line.
        root.background = dark ? UI.brush(28, 27, 26) : UI.brush(247, 247, 247)
        root.borderBrush = dark ? UI.brush(0, 0, 0, alpha: 235) : UI.brush(0, 0, 0, alpha: 31)
        root.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
        build()
        openedAt = GetTickCount64()
        shown = false
        buttonWasDown = Self.isDown(0x01)
        startWatching()
    }

    /// A key while it is open: every key is the switcher's (the Mac's local monitor).
    /// `direction` is the move the user's own switcher keys ask for, if this is one.
    func handle(_ key: KeyPress, direction: Int?) {
        if let direction { state.move(direction); redraw(); return }
        switch key.keyCode {
        case 0x09: state.move(key.shift ? -1 : 1)  // Tab
        case 0x27: state.move(1)  // Right
        case 0x25: state.move(-1)  // Left
        case 0x1B: return finish(commit: false)  // Escape
        case 0x0D: return finish(commit: true)  // Return
        default: return
        }
        redraw()
    }

    /// Another window, a space change or the window closing: it goes without switching.
    func cancel() {
        guard state.isOpen else { return }
        finish(commit: false)
    }

    // MARK: Cards

    private func build() {
        row.children.clear()
        cardViews = cards.enumerated().map { i, card in makeCard(card, index: i) }
        for v in cardViews { row.children.append(v) }
        redraw()
    }

    private func makeCard(_ card: Card, index: Int) -> Border {
        let view = makeCardBody(card, index: index)
        if let title = card.spaceTitle, let content = view.child as? Grid { content.children.append(spacePill(title)) }
        return view
    }

    /// The Mac's space pill (TabSwitcherView): 20 tall, 6 in from the picture's top left corner, in the
    /// pill of Arc's hover tips, the space's name in 11 pt medium.
    private func spacePill(_ title: String) -> Border {
        let pill = Border()
        pill.height = 20
        pill.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        pill.background = dark ? UI.brush(26, 26, 26, alpha: 217) : UI.brush(255, 255, 255, alpha: 230)
        pill.padding = Thickness(left: 7, top: 0, right: 7, bottom: 0)
        pill.horizontalAlignment = .left
        pill.verticalAlignment = .top
        pill.maxWidth = Double(L.thumbnail.width) - 12
        pill.margin = Thickness(left: Double(L.thumbnailOrigin.x) + 6, top: Double(L.thumbnailOrigin.y) + 6, right: 0, bottom: 0)
        let text = UI.text(title, size: 11, color: dark ? UI.brush(255, 255, 255, alpha: 235) : UI.brush(0, 0, 0, alpha: 217))
        text.fontWeight = UWP.FontWeight(weight: 500)
        text.verticalAlignment = .center
        pill.child = text
        return pill
    }

    private func makeCardBody(_ card: Card, index: Int) -> Border {
        let view = Border()
        view.width = Double(L.card.width)
        view.height = Double(L.card.height)
        view.cornerRadius = CornerRadius(topLeft: Double(L.cardCornerRadius), topRight: Double(L.cardCornerRadius),
                                         bottomRight: Double(L.cardCornerRadius), bottomLeft: Double(L.cardCornerRadius))
        let content = Grid()
        guard card.panes.count < 2 else {
            makeSplitCard(card, in: content)
            view.child = content
            return watchPointer(view, index: index)
        }
        // No page pictures yet on Windows: Arc's empty card for a tab not seen since launch.
        let thumb = Border()
        thumb.width = Double(L.thumbnail.width)
        thumb.height = Double(L.thumbnail.height)
        let r = Double(L.thumbnailCornerRadius)
        thumb.cornerRadius = CornerRadius(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
        thumb.background = dark ? UI.brush(28, 28, 28) : UI.brush(230, 230, 230)
        thumb.horizontalAlignment = .left
        thumb.verticalAlignment = .top
        thumb.margin = Thickness(left: Double(L.thumbnailOrigin.x), top: Double(L.thumbnailOrigin.y), right: 0, bottom: 0)
        content.children.append(thumb)

        // The favicon and title fill what is left under the picture, centred.
        let line = StackPanel()
        line.orientation = .horizontal
        line.spacing = 8
        line.verticalAlignment = .center
        let rowTop = Double(L.thumbnailOrigin.y + L.thumbnail.height)
        line.margin = Thickness(left: 13.5, top: rowTop, right: 10.5, bottom: 0)
        if let bitmap = Favicons.shared.bitmap(forKey: card.iconKey, onDark: dark) {
            line.children.append(UI.image(bitmap, size: Double(L.favicon)))
        } else {
            // Arc's switcher draws a missing favicon as a faint rounded square, not a globe.
            let square = Border()
            square.width = Double(L.favicon)
            square.height = Double(L.favicon)
            square.cornerRadius = CornerRadius(topLeft: 4.5, topRight: 4.5, bottomRight: 4.5, bottomLeft: 4.5)
            square.background = dark ? UI.brush(255, 255, 255, alpha: 36) : UI.brush(0, 0, 0, alpha: 26)
            line.children.append(square)
        }
        let title = UI.text(card.title.isEmpty ? "New Tab" : card.title, size: 14,
                            color: dark ? UI.brush(255, 255, 255) : UI.brush(0, 0, 0, alpha: 217))
        title.fontWeight = UWP.FontWeight(weight: 500)
        title.maxWidth = Double(L.card.width) - 13.5 - Double(L.favicon) - 8 - 10.5
        title.verticalAlignment = .center
        line.children.append(title)
        content.children.append(line)
        view.child = content
        return watchPointer(view, index: index)
    }

    /// A split's card (#554, Arc 1.172): the picture's place is a dark frame with each pane's own
    /// (empty) picture in it, as wide as the pane's share (CraCore SwitcherSplitLayout), and each
    /// pane's favicon centred under its picture; no titles.
    private func makeSplitCard(_ card: Card, in content: Grid) {
        let r = Double(L.thumbnailCornerRadius)
        let frame = Border()
        frame.width = Double(L.thumbnail.width)
        frame.height = Double(L.thumbnail.height)
        frame.cornerRadius = CornerRadius(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
        frame.background = dark ? UI.brush(12, 12, 12) : UI.brush(200, 200, 200)
        frame.horizontalAlignment = .left
        frame.verticalAlignment = .top
        frame.margin = Thickness(left: Double(L.thumbnailOrigin.x), top: Double(L.thumbnailOrigin.y), right: 0, bottom: 0)
        content.children.append(frame)
        let panes = SwitcherSplitLayout.paneFrames(in: L.thumbnail, widths: card.panes.map { CGFloat($0.width) })
        let rowTop = Double(L.thumbnailOrigin.y + L.thumbnail.height)
        let iconTop = rowTop + (Double(L.card.height) - rowTop - Double(L.favicon)) / 2
        for (pane, f) in zip(card.panes, panes) {
            let picture = Border()
            picture.width = Double(f.width)
            picture.height = Double(f.height)
            let pr = max(0, r - Double(SwitcherSplitLayout.inset))
            picture.cornerRadius = CornerRadius(topLeft: pr, topRight: pr, bottomRight: pr, bottomLeft: pr)
            picture.background = dark ? UI.brush(28, 28, 28) : UI.brush(230, 230, 230)
            picture.horizontalAlignment = .left
            picture.verticalAlignment = .top
            picture.margin = Thickness(left: Double(L.thumbnailOrigin.x + f.minX), top: Double(L.thumbnailOrigin.y + f.minY), right: 0, bottom: 0)
            content.children.append(picture)
            let icon: FrameworkElement
            if let bitmap = Favicons.shared.bitmap(forKey: pane.iconKey, onDark: dark) {
                icon = UI.image(bitmap, size: Double(L.favicon))
            } else {
                let square = Border()
                square.width = Double(L.favicon)
                square.height = Double(L.favicon)
                square.cornerRadius = CornerRadius(topLeft: 4.5, topRight: 4.5, bottomRight: 4.5, bottomLeft: 4.5)
                square.background = dark ? UI.brush(255, 255, 255, alpha: 36) : UI.brush(0, 0, 0, alpha: 26)
                icon = square
            }
            icon.horizontalAlignment = .left
            icon.verticalAlignment = .top
            icon.margin = Thickness(left: Double(L.thumbnailOrigin.x + f.midX) - Double(L.favicon) / 2, top: iconTop, right: 0, bottom: 0)
            content.children.append(icon)
        }
    }

    /// Hover selects the card, a click picks it.
    private func watchPointer(_ view: Border, index: Int) -> Border {
        view.pointerMoved.addHandler { [weak self] _, _ in self?.hover(index) }
        view.pointerPressed.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.state.select(index)
            self.finish(commit: true)
        }
        return view
    }

    private func redraw() {
        for (i, view) in cardViews.enumerated() {
            view.background = i == state.selectedIndex ? highlight : nil
        }
    }

    private func hover(_ index: Int) {
        guard shown else { return }
        var now = POINT()
        guard GetCursorPos(&now) else { return }
        if let start = pointerAtShow {
            guard now.x != start.x || now.y != start.y else { return }
            pointerAtShow = nil
        }
        guard index != state.selectedIndex else { return }
        state.select(index)
        redraw()
    }

    // MARK: Showing

    private func show() {
        guard let window, let f = frame() else { return }
        let size = L.panelSize(count: cards.count)
        let width = Int32((Double(size.width) * f.scale).rounded()), height = Int32((Double(size.height) * f.scale).rounded())
        // Centred on the whole window, like Arc (sidebar included).
        window.place(origin: PointInt32(x: f.x + (f.width - width) / 2, y: f.y + (f.height - height) / 2),
                     size: SizeInt32(width: width, height: height))
        var p = POINT()
        pointerAtShow = GetCursorPos(&p) ? p : nil
        window.showInactive()
        shown = true
    }

    private func finish(commit: Bool) {
        stopWatching()
        let chosen = state.close(commit: commit)
        if shown { window?.hide() }
        shown = false
        pointerAtShow = nil
        cards = []
        cardViews = []
        row.children.clear()
        if let chosen { onCommit(chosen) }
    }

    // MARK: Watching

    private func startWatching() {
        stopWatching()
        timer = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.createTimer()
        timer?.interval = TimeSpan(duration: 16 * 10_000)
        timer?.isRepeating = true
        timer?.tick.addHandler { [weak self] _, _ in self?.tick() }
        try? timer?.start()
    }

    private func stopWatching() {
        try? timer?.stop()
        timer = nil
    }

    private func tick() {
        guard state.isOpen else { return stopWatching() }
        // Letting go of Ctrl switches (a quick tap before the panel shows, too).
        guard Self.controlHeld else { return finish(commit: true) }
        // Another app or window in front: the switcher goes.
        let front = UInt(bitPattern: GetForegroundWindow())
        if front != ownerHwnd && front != window?.hwnd { return finish(commit: false) }
        // A click anywhere but a card closes it (a card's own press switches first).
        let down = Self.isDown(0x01) || Self.isDown(0x02)
        if down && !buttonWasDown && !(shown && window?.hasPointer == true) { return finish(commit: false) }
        buttonWasDown = down
        // Arc waits a moment, so a quick tap never flashes the panel.
        if !shown && GetTickCount64() &- openedAt >= UInt64(L.showDelay * 1000) { show() }
    }

    private static var controlHeld: Bool { isDown(0x11) }
    private static func isDown(_ vk: Int32) -> Bool { GetAsyncKeyState(vk) < 0 }
    private static func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
}
