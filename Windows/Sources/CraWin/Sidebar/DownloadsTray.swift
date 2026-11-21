import CraCEFWin
import CraCore
import Foundation
import Observation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

extension DownloadHistory {
    /// downloads.json in the data folder, as on the Mac.
    static let shared = DownloadHistory(file: JSONStore("downloads.json", in: WinPaths.supportDir))
}

/// Arc's downloads list (DownloadsTrayView on the Mac): hovering the downloads button lists
/// the recent downloads over the bottom of the sidebar, newest at the bottom; it opens 0.2 s
/// into the hover and closes 0.07 s after the pointer leaves. Rows are 40 px with 16 between,
/// a tile, the file name and "54 seconds ago" or the progress under it. A click opens a
/// finished file; its menu shows it in its folder.
@MainActor
final class DownloadsTray {
    /// In the sidebar's footer: a download glyph, with the progress while a download runs.
    /// Arc's Library button: hovering it lists the downloads, a click opens the Library.
    let button: Button
    var onClick: () -> Void = {}
    /// Over the bottom of the tab list.
    let list = StackPanel()
    private let history: DownloadHistory
    private let thumbnails: DownloadThumbnails
    private let dispatcher: WinAppSDK.DispatcherQueue
    private let glyph = FontIcon()
    private let progress = TextBlock()
    /// Arc's badge on the bin while downloads run (#272, the Mac's DownloadProgressBadgeView):
    /// a disc on the glyph's bottom right corner with the ring and an arrow, a check when done.
    private let badge = Grid()
    private let badgeDisc = WinUI.Ellipse()  // not GDI's Ellipse
    /// The ring's track (an outline) and its arc, drawn as a path: the projection has no ProgressRing.
    private let track = WinUI.Ellipse()  // not GDI's Ellipse
    private let ring = WinUI.Path()
    private var ringValue = -1.0
    private let badgeMark = FontIcon()
    private var badgeState = DownloadBadge()
    /// Re-reads the badge while it shows (a download can go stuck without a report) and ends the
    /// check after `DownloadBadge.doneFor`.
    private var badgeTimer: WinAppSDK.DispatcherQueueTimer?
    private var rows: [Row] = []
    private var isOpen = false
    /// The pointer in the XAML's coordinates (DIPs from the sidebar's top left), nil when it
    /// can't be read. XAML's PointerEntered and PointerExited come and go as the rows redraw
    /// under a still pointer, so the list asks where the pointer is instead.
    var pointer: () -> (x: Double, y: Double)? = { nil }
    /// Waits out the hover (0.2 s to open, 0.07 s to close), then checks every 0.07 s while the
    /// list is up; the ages tick once a second.
    private var hoverTimer: WinAppSDK.DispatcherQueueTimer?
    private var hoverStarted: Date?
    private var awayChecks = 0
    private var lastAges = Date.distantPast
    private var palette = SidebarPalette(SpaceTheme.presets[0])
    private var fill: Brush = UI.clear

    init(history: DownloadHistory, dispatcher: WinAppSDK.DispatcherQueue) {
        self.history = history
        self.dispatcher = dispatcher
        thumbnails = DownloadThumbnails(dispatcher: dispatcher)
        glyph.glyph = "\u{E896}"
        glyph.fontSize = 14
        progress.fontSize = 11
        progress.verticalAlignment = .center
        let content = StackPanel()
        content.orientation = .horizontal
        content.spacing = 6
        let size = 16.0
        badge.width = size
        badge.height = size
        badge.horizontalAlignment = .right
        badge.verticalAlignment = .bottom
        // Over the glyph's corner, 4 DIPs out, as the Mac's sits on the bin's.
        badge.margin = Thickness(left: 0, top: 0, right: -8, bottom: -6)
        badge.isHitTestVisible = false
        badge.visibility = .collapsed
        badgeDisc.width = size
        badgeDisc.height = size
        // The Mac's: 1.5 wide, its centre line 2.25 inside the badge's edge.
        let inset = 2.25 - 0.75
        track.width = size - 2 * inset
        track.height = size - 2 * inset
        track.strokeThickness = 1.5
        track.horizontalAlignment = HorizontalAlignment.center
        track.verticalAlignment = VerticalAlignment.center
        ring.width = size
        ring.height = size
        ring.strokeThickness = 1.5
        badgeMark.fontSize = 7
        badgeMark.horizontalAlignment = .center
        badgeMark.verticalAlignment = .center
        badge.children.append(badgeDisc)
        badge.children.append(track)
        badge.children.append(ring)
        badge.children.append(badgeMark)
        try? AutomationProperties.setName(badge, "Downloads")
        let icon = Grid()
        icon.verticalAlignment = .center
        icon.children.append(glyph)
        icon.children.append(badge)
        content.children.append(icon)
        content.children.append(progress)
        button = UI.button(content, padding: Thickness(left: 6, top: 5, right: 6, bottom: 5)) {}
        button.verticalAlignment = .center
        button.horizontalAlignment = .left
        // No tooltip: it would cover the pointer and end the hover.
        list.orientation = .vertical
        list.spacing = 16
        list.verticalAlignment = .bottom
        list.padding = Thickness(left: 0, top: 12, right: 0, bottom: 2)
        list.visibility = .collapsed
        button.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            self.setOpen(false)
            self.stopWatching()
            self.onClick()
        }
        try? AutomationProperties.setName(button, "Library")
        button.pointerEntered.addHandler { [weak self] _, _ in self?.startWatching() }
        list.pointerEntered.addHandler { [weak self] _, _ in self?.startWatching() }
        observe()
    }

    /// The sidebar's colours for the focused space.
    func apply(_ palette: SidebarPalette, fill: Brush) {
        self.palette = palette
        self.fill = fill
        list.background = fill
        glyph.foreground = palette.secondaryText
        progress.foreground = palette.secondaryText
        // The Mac's: a white (or dark grey) disc, the ring and mark in 85 % ink, the track 15 %.
        badgeDisc.fill = palette.isDark ? UI.brush(41, 41, 41) : UI.brush(255, 255, 255)
        let ink: UInt8 = palette.isDark ? 255 : 0
        ring.stroke = UI.brush(ink, ink, ink, alpha: 217)
        track.stroke = UI.brush(ink, ink, ink, alpha: 38)
        badgeMark.foreground = UI.brush(ink, ink, ink, alpha: 217)
        for row in rows { row.apply(palette) }
    }

    // MARK: The list

    private func observe() {
        let (recent, running, live, _) = withObservationTracking {
            // The thumbnails' revision too: a row redraws when its picture arrives.
            (history.recent, history.live.filter(\.running), history.live, thumbnails.revision)
        } onChange: { [weak self] in
            // Inside the change: draw once it is done.
            onMain { _ = try? self?.dispatcher.tryEnqueue { self?.observe() } }
        }
        show(recent)
        showBadge(live)
        showText(running)
        if recent.isEmpty, isOpen { setOpen(false) }
    }

    /// The button says how far the running downloads are while the badge doesn't: it leaves a
    /// stuck one (#491) to the text and the list.
    private func showText(_ running: [DownloadList.Live]) {
        if running.isEmpty || badge.visibility == .visible {
            progress.visibility = .collapsed
        } else {
            let received = running.reduce(Int64(0)) { $0 + $1.received }, total = running.reduce(Int64(0)) { $0 + max(0, $1.total) }
            progress.text = total > 0 ? "\(min(100, Int(received * 100 / total)))%" : DownloadRow.bytes(received)
            progress.visibility = .visible
        }
    }

    // MARK: The badge

    private func showBadge(_ live: [DownloadList.Live]) {
        badgeState.update(live, now: Date())
        switch badgeState.look {
        case .hidden:
            badge.visibility = Visibility.collapsed
            stopBadgeTimer()
            return
        case .running(let fraction):
            drawRing(fraction)
            ring.visibility = Visibility.visible
            track.visibility = Visibility.visible
            badgeMark.glyph = "\u{E74B}"  // Down
            startBadgeTimer(every: 1, repeating: true)
        case .done:
            ring.visibility = Visibility.collapsed
            track.visibility = Visibility.collapsed
            badgeMark.glyph = "\u{E73E}"  // CheckMark
            startBadgeTimer(every: DownloadBadge.doneFor, repeating: false)
        }
        badge.visibility = Visibility.visible
    }

    /// The arc from 12 o'clock, clockwise, `fraction` of the way round (the Mac's strokeEnd), in
    /// steps of at most 6°.
    private func drawRing(_ fraction: Double) {
        let fraction = min(1, max(0, fraction))
        guard abs(fraction - ringValue) > 0.002 else { return }
        ringValue = fraction
        let size = 16.0, radius = size / 2 - 2.25, centre = size / 2
        func point(_ angle: Double) -> WindowsFoundation.Point {
            WindowsFoundation.Point(x: Float(centre + radius * sin(angle)), y: Float(centre - radius * cos(angle)))
        }
        let sweep = fraction * 2 * Double.pi
        let steps = max(1, Int((sweep / (Double.pi / 30)).rounded(.up)))
        let figure = PathFigure()
        figure.startPoint = point(0)
        figure.isClosed = false
        figure.isFilled = false
        let segments = PathSegmentCollection()
        if fraction > 0 {
            for i in 1...steps {
                let line = LineSegment()
                line.point = point(sweep * Double(i) / Double(steps))
                segments.append(line)
            }
        }
        figure.segments = segments
        let figures = PathFigureCollection()
        figures.append(figure)
        let geometry = PathGeometry()
        geometry.figures = figures
        ring.data = geometry
    }

    private func startBadgeTimer(every seconds: TimeInterval, repeating: Bool) {
        if let badgeTimer, badgeTimer.isRepeating == repeating { return }
        stopBadgeTimer()
        badgeTimer = try? dispatcher.createTimer()
        badgeTimer?.interval = TimeSpan(duration: Int64(seconds * 10_000_000))
        badgeTimer?.isRepeating = repeating
        badgeTimer?.tick.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.badgeState.look == .done {
                self.badgeState.doneShown()
                self.stopBadgeTimer()
            }
            self.showBadge(self.history.live)
            self.showText(self.history.live.filter(\.running))
        }
        try? badgeTimer?.start()
    }

    private func stopBadgeTimer() {
        try? badgeTimer?.stop()
        badgeTimer = nil
    }

    /// One row per listed download. Also on the ticks: a file deleted since drops out, which
    /// nothing observable reports.
    private func show(_ recent: [DownloadHistory.Listed]) {
        while rows.count < recent.count {
            let row = Row()
            row.apply(palette)
            rows.append(row)
            list.children.append(row.root)
        }
        while rows.count > recent.count {
            rows.removeLast()
            list.children.removeAtEnd()
        }
        let now = Date()
        for (row, item) in zip(rows, recent) { row.show(item, now: now, thumbnails: thumbnails) }
    }

    // MARK: Hover

    private func startWatching() {
        if hoverStarted == nil { hoverStarted = Date() }
        guard hoverTimer == nil else { return }
        hoverTimer = try? dispatcher.createTimer()
        hoverTimer?.interval = TimeSpan(duration: 70 * 10_000)
        hoverTimer?.isRepeating = true
        hoverTimer?.tick.addHandler { [weak self] _, _ in self?.check() }
        try? hoverTimer?.start()
    }

    private func stopWatching() {
        try? hoverTimer?.stop()
        hoverTimer = nil
        hoverStarted = nil
    }

    private func check() {
        let over = isOver(button) || (isOpen && isOver(list))
        if over {
            awayChecks = 0
            if !isOpen, let started = hoverStarted, Date().timeIntervalSince(started) >= 0.2 { setOpen(true) }
        } else {
            hoverStarted = nil
            // Away for a whole check (0.07 s): closed.
            awayChecks += 1
            if awayChecks >= 1 {
                if isOpen { setOpen(false) }
                stopWatching()
                return
            }
        }
        if isOpen, Date().timeIntervalSince(lastAges) >= 1 {
            lastAges = Date()
            show(history.recent)
            if history.recent.isEmpty { setOpen(false) }
        }
    }

    private func isOver(_ element: FrameworkElement) -> Bool {
        guard element.visibility == .visible, let p = pointer(),
              let transform = try? element.transformToVisual(nil),
              let origin = try? transform.transformPoint(WindowsFoundation.Point(x: 0, y: 0)) else { return false }
        let x = p.x - Double(origin.x), y = p.y - Double(origin.y)
        return x >= 0 && y >= 0 && x < element.actualWidth && y < element.actualHeight
    }

    private func setOpen(_ open: Bool) {
        let open = open && !history.recent.isEmpty
        guard open != isOpen else { return }
        isOpen = open
        list.visibility = open ? .visible : .collapsed
        if open {
            lastAges = Date()
            show(history.recent)
            // Kept open while the pointer is over the button or the list.
            awayChecks = 0
            startWatching()
        }
    }

    /// One download: a tile, the name, and the line under it.
    @MainActor
    final class Row {
        let root = Grid()
        private let tile = Border()
        private let tileIcon = FontIcon()
        private let picture = WinUI.Image()
        private let name = TextBlock()
        private let subtitle = TextBlock()
        private var path: String?
        private var item: DownloadHistory.Listed?
        /// Kept here: a WinRT object built from Swift is only a wrapper, so a weak capture of it
        /// is nil once nothing in Swift holds it, however long XAML keeps the control.
        private let menu = MenuFlyout()

        init() {
            root.height = 40
            root.background = UI.clear
            for width in [UI.pixels(61), UI.star] { root.columnDefinitions.append(UI.column(width)) }
            tile.width = 40
            tile.height = 40
            tile.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
            tile.horizontalAlignment = .left
            tile.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
            tile.background = UI.brush(255, 255, 255, alpha: 230)
            tileIcon.glyph = "\u{E8A5}"
            tileIcon.fontSize = 18
            tileIcon.foreground = UI.brush(90, 90, 96)
            tile.child = tileIcon
            picture.width = DownloadThumbnails.tile
            picture.height = DownloadThumbnails.tile
            picture.stretch = .uniform
            picture.margin = tile.margin
            picture.horizontalAlignment = .left
            picture.visibility = .collapsed
            name.fontSize = 14
            name.textTrimming = .characterEllipsis
            subtitle.fontSize = 12
            subtitle.textTrimming = .characterEllipsis
            let text = StackPanel()
            text.verticalAlignment = .center
            text.children.append(name)
            text.children.append(subtitle)
            root.children.append(tile)
            root.children.append(picture)
            root.children.append(text)
            try? Grid.setColumn(text, 1)
            root.tapped.addHandler { [weak self] _, args in
                guard let self, let path = self.path else { return }
                args?.handled = true
                Shell.open(path)
            }
            // Arc's download menu, built as it opens (DownloadMenu): Pause, Resume and Cancel
            // while it runs, Open, Copy, Show in Folder, Hide and Move to Recycle Bin once done.
            menu.opening.addHandler { [weak self] _, _ in
                guard let self, let item = self.item else { return }
                DownloadRowMenu.fill(self.menu, for: item)
            }
            root.contextFlyout = menu
        }

        func apply(_ palette: SidebarPalette) {
            name.foreground = palette.text
            subtitle.foreground = palette.secondaryText
        }

        func show(_ item: DownloadHistory.Listed, now: Date, thumbnails: DownloadThumbnails) {
            if name.text != item.name { name.text = item.name }
            // A finished file's preview or icon; a running one shows its type's icon, as on the Mac.
            let image: WriteableBitmap?
            switch item {
            case .finished(let entry): image = thumbnails.thumbnail(for: entry.path)
            case .live(let live): image = thumbnails.typeIcon(for: live.name)
            }
            if let image {
                picture.source = image
                picture.visibility = .visible
                tile.visibility = .collapsed
            } else {
                picture.visibility = .collapsed
                tile.visibility = .visible
            }
            let line = item.subtitle(now: now)
            if subtitle.text != line { subtitle.text = line }
            if case .finished(let entry) = item { path = entry.path } else { path = nil }
            self.item = item
        }
    }
}

/// The downloads list's pictures (the Mac's DownloadThumbnails with Quick Look): Explorer's
/// preview of each file, else its icon, cropped to a square with 6 DIP corners, made off the UI
/// thread on first use.
@MainActor
@Observable
final class DownloadThumbnails {
    /// The tile's side in DIPs (DownloadsTrayMetrics.thumbnail).
    static let tile = 40.0
    /// Pixels asked for: the tile at up to 240 % scaling.
    private static let side = 96

    /// Bumped as pictures arrive.
    private(set) var revision = 0
    @ObservationIgnored private var images: [String: WriteableBitmap] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private let dispatcher: WinAppSDK.DispatcherQueue

    init(dispatcher: WinAppSDK.DispatcherQueue) {
        self.dispatcher = dispatcher
    }

    func thumbnail(for path: String) -> WriteableBitmap? { image(key: path, file: path) }

    /// The icon Explorer shows for files with this name's extension.
    func typeIcon(for name: String) -> WriteableBitmap? {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        // A path that doesn't exist: the bridge falls back to the type's icon.
        return image(key: "type:" + ext, file: "cra-download." + (ext.isEmpty ? "bin" : ext))
    }

    private func image(key: String, file: String) -> WriteableBitmap? {
        if let image = images[key] { return image }
        guard !file.isEmpty, loading.insert(key).inserted else { return nil }
        let side = Self.side, tile = Self.tile
        let queue = UncheckedSendable(value: dispatcher)
        let arrived: @MainActor (Pixels?) -> Void = { [weak self] pixels in
            guard let self else { return }
            if let image = pixels?.bitmap() {
                self.images[key] = image
                self.revision += 1
            }
            // A miss stays in `loading`: it isn't asked for again.
        }
        let done = UncheckedSendable(value: arrived)
        DispatchQueue.global(qos: .utility).async {
            let pixels = Pixels.file(file, side: side).map { picture in
                let square = picture.squareCrop()
                return square.rounded(radius: Double(square.width) * 6 / tile)
            }
            _ = try? queue.value.tryEnqueue { onMain { done.value(pixels) } }
        }
        return nil
    }
}

/// Opening files the way Explorer does.
enum Shell {
    static func open(_ path: String) { run("open", path, nil) }

    /// Explorer on the folder a profile saves to: its Download location from Settings ▸ Profiles
    /// while that folder is there, else the user's Downloads folder (CraCEFWin's DownloadFolderFor).
    static func openDownloadsFolder(_ location: DownloadLocation = DownloadLocation()) {
        var isFolder: ObjCBool = false
        if let folder = location.folder, FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue {
            run("open", "explorer.exe", "\"\(folder)\"")
        } else {
            run("open", "explorer.exe", "shell:Downloads")
        }
    }

    /// An Explorer window on the file's folder, the file selected (explorer /select didn't
    /// select it in a window already open on the folder).
    static func showInFolder(_ path: String) { cra_shell_show_in_folder(path) }

    private static func run(_ verb: String, _ file: String, _ parameters: String?) {
        verb.withCString(encodedAs: UTF16.self) { verb in
            file.withCString(encodedAs: UTF16.self) { file in
                if let parameters {
                    parameters.withCString(encodedAs: UTF16.self) { _ = ShellExecuteW(nil, verb, file, $0, nil, SW_SHOWNORMAL) }
                } else {
                    _ = ShellExecuteW(nil, verb, file, nil, nil, SW_SHOWNORMAL)
                }
            }
        }
    }
}
