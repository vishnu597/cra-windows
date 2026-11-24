import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

/// Arc's folder preview (the Mac's FolderPreviewController; what it lists, its search and its
/// size in CraCore's FolderPreviewList). Resting the pointer 0.45 s on a closed folder lists every
/// tab in it, nested folders included, most recently used first, under a "Search <folder>…"
/// field that already has the keys. ↑↓ and Enter pick a tab; Escape, leaving or a click elsewhere
/// closes it; typing or arrowing keeps it open after the pointer leaves. A row's menu has Copy
/// Link, Open in Split View, Duplicate and Archive.
@MainActor
final class FolderPreview {
    private unowned let sidebar: SidebarView
    /// The browser window the card floats over (BrowserWindow sets it).
    var host: () -> HostWindow? = { nil }
    private var card: FolderPreviewCard?
    private var window: FloatingWindow?
    private var timer: WinAppSDK.DispatcherQueueTimer?
    /// The closed folder row under the pointer.
    private var hovered: UUID?
    /// A folder waiting out the open delay, since when.
    private var pending: (id: UUID, since: Double)?
    /// The folder whose card is open.
    private(set) var folderID: UUID?
    /// Since when the pointer has been off both the folder and the card.
    private var outsideSince: Double?
    /// Typing or arrowing keeps the card open after the pointer leaves.
    var extended = false
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init(sidebar: SidebarView) {
        self.sidebar = sidebar
    }

    var isOpen: Bool { folderID != nil && window?.isVisible == true }

    /// The pointer came onto a folder row.
    func entered(_ id: UUID) {
        hovered = id
        if id == folderID, isOpen {
            outsideSince = nil
            return
        }
        guard previewable(id), sidebar.drag.source == nil, GetKeyState(0x01) >= 0, GetKeyState(0x02) >= 0 else { return }
        pending = (id, now)
        startTicking()
    }

    /// The pointer left a folder row.
    func exited(_ id: UUID) {
        if hovered == id { hovered = nil }
        if pending?.id == id { pending = nil }
    }

    /// A press anywhere on the folder: it opens or closes, and the card goes.
    func pressed() {
        pending = nil
        close()
    }

    /// Only a closed folder with tabs previews, while the setting is on.
    private func previewable(_ id: UUID) -> Bool {
        guard sidebar.store.settings.folderPreviews, let folder = sidebar.store.item(id), folder.isFolder,
              !sidebar.store.isExpanded(id), sidebar.renaming.itemID != id else { return false }
        return !sidebar.store.tabs(under: id).isEmpty
    }

    private func startTicking() {
        if timer == nil {
            timer = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.createTimer()
            timer?.interval = TimeSpan(duration: 30 * 10_000)
            timer?.isRepeating = true
            timer?.tick.addHandler { [weak self] _, _ in self?.tick() }
        }
        try? timer?.start()
    }

    private func tick() {
        if let p = pending, now - p.since >= FolderPreviewList.openDelay {
            pending = nil
            if hovered == p.id, previewable(p.id), GetKeyState(0x01) >= 0 { open(p.id) }
        }
        if isOpen, let folderID {
            // Opened, renamed or emptied meanwhile: nothing left to preview.
            guard previewable(folderID) else { return close() }
            if hovered == folderID || window?.hasPointer == true || extended {
                outsideSince = nil
            } else if let since = outsideSince {
                if now - since >= FolderPreviewList.closeGrace { close() }
            } else {
                outsideSince = now
            }
        }
        if pending == nil, !isOpen { try? timer?.stop() }
    }

    // MARK: Opening

    private func open(_ id: UUID) {
        guard let host = host(), let folder = sidebar.store.item(id), let row = sidebar.folderRow(id) else { return }
        let entries = sidebar.store.folderPreviewEntries(id)
        guard !entries.isEmpty else { return }
        let card = self.card ?? FolderPreviewCard(preview: self, favicons: sidebar.favicons)
        self.card = card
        if window == nil {
            do {
                window = try FloatingWindow(owner: host, content: card.root)
                // A click on the page, the sidebar or another app: the card goes.
                window?.onDeactivate = { [weak self] in self?.close(restoreFocus: false) }
            } catch {
                print("Cra: the folder preview window could not be made: \(error)")
                return
            }
        }
        folderID = id
        extended = false
        outsideSince = nil
        card.show(title: folder.displayTitle, entries: entries)
        guard let frame = frame(for: row, rows: entries.count, host: host) else { return close() }
        window?.place(origin: frame.origin, size: frame.size)
        window?.show { [weak card] in card?.focusSearch() }
        startTicking()
    }

    /// Beside the sidebar (left of it when it is on the right), centred on the folder's row and
    /// kept 18 DIPs inside the window, in physical pixels on screen.
    private func frame(for row: FrameworkElement, rows: Int, host: HostWindow) -> (origin: PointInt32, size: SizeInt32)? {
        guard let hwnd = HWND(bitPattern: host.hwnd),
              let rowTransform = try? row.transformToVisual(nil),
              let rowAt = try? rowTransform.transformPoint(WindowsFoundation.Point(x: 0, y: 0)),
              let sideTransform = try? sidebar.root.transformToVisual(nil),
              let sideAt = try? sideTransform.transformPoint(WindowsFoundation.Point(x: 0, y: 0)) else { return nil }
        let scale = host.scale
        var client = POINT(x: 0, y: 0)
        _ = ClientToScreen(hwnd, &client)
        let column = host.columnOrigin
        // XAML's coordinates start at the column's top left, in DIPs; everything below is DIPs on screen.
        let originX = Double(client.x + column.x) / scale, originY = Double(client.y + column.y) / scale
        let rowMid = originY + Double(rowAt.y) + row.actualHeight / 2
        let sideLeft = originX + Double(sideAt.x), sideRight = sideLeft + sidebar.root.actualWidth
        let width = Double(FolderPreviewList.width), height = Double(FolderPreviewList.height(rows: rows))
        let gap = Double(FolderPreviewList.gapFromSidebar)
        let x = host.sidebarSide == .right ? sideLeft - gap - width : sideRight + gap
        let windowTop = Double(client.y) / scale
        let windowBottom = windowTop + Double(host.appWindow.clientSize.height) / scale
        let y = Double(FolderPreviewList.top(rowMidY: CGFloat(rowMid), height: CGFloat(height),
                                             windowTop: CGFloat(windowTop), windowBottom: CGFloat(windowBottom)))
        return (PointInt32(x: Int32((x * scale).rounded()), y: Int32((y * scale).rounded())),
                SizeInt32(width: Int32((width * scale).rounded()), height: Int32((height * scale).rounded())))
    }

    /// Closes the card; `restoreFocus` gives the keyboard back to the browser window (Escape, a pick).
    func close(restoreFocus: Bool = true) {
        pending = nil
        guard folderID != nil else { return }
        folderID = nil
        extended = false
        outsideSince = nil
        let wasOpen = window?.isVisible == true
        window?.hide()
        if restoreFocus, wasOpen, let host = host(), let hwnd = HWND(bitPattern: host.hwnd) {
            _ = SetForegroundWindow(hwnd)
        }
    }

    // MARK: Actions

    func pick(_ id: UUID) {
        close()
        sidebar.store.selectTab(id, window: sidebar.windowID)
    }

    func copyLink(_ url: String) {
        _ = WinShell.copy(url)
    }

    func openInSplitView(_ id: UUID) {
        close()
        guard let current = sidebar.store.selectedTabID(window: sidebar.windowID), current != id else {
            sidebar.store.selectTab(id, window: sidebar.windowID)
            return
        }
        sidebar.actions?.openInSplitView(id)
    }

    func duplicate(_ id: UUID) {
        close()
        if let copy = sidebar.store.duplicateTab(id) { sidebar.store.selectTab(copy.id, window: sidebar.windowID) }
    }

    func archive(_ id: UUID) {
        sidebar.store.archiveTab(id, reason: .manual)
        guard let folderID, sidebar.store.item(folderID) != nil else { return close() }
        let entries = sidebar.store.folderPreviewEntries(folderID)
        if entries.isEmpty { close() } else { card?.replace(entries) }
    }
}

/// The card: a search field over the folder's tabs, drawn dark whatever the space's theme, as Arc does.
@MainActor
final class FolderPreviewCard {
    let root = Grid()
    private unowned let preview: FolderPreview
    private let favicons: Favicons
    private let field = TextBox()
    private let scroll = ScrollViewer()
    private let rowsPanel = StackPanel()
    private let empty = UI.text("No tabs matching that search 🤔", size: 13, color: FolderPreviewCard.secondary)
    private var entries: [FolderPreviewList.Entry] = []
    private var shown: [FolderPreviewList.Entry] = []
    private var rows: [Border] = []
    private var selected = 0
    private var hoveredRow: Int?

    static let fill = UI.brush(30, 30, 30)
    static let title = UI.brush(255, 255, 255, alpha: 212)
    static let secondary = UI.brush(255, 255, 255, alpha: 140)
    static let rowFill = UI.brush(255, 255, 255, alpha: 20)
    static let hairline = UI.brush(255, 255, 255, alpha: 33)

    init(preview: FolderPreview, favicons: Favicons) {
        self.preview = preview
        self.favicons = favicons
        root.background = Self.fill
        root.width = Double(FolderPreviewList.width)
        root.requestedTheme = .dark
        root.rowDefinitions.append(UI.row(UI.pixels(Double(FolderPreviewList.searchHeight))))
        root.rowDefinitions.append(UI.row(UI.pixels(1)))
        root.rowDefinitions.append(UI.row(UI.star))

        let search = Grid()
        let glyph = FontIcon()
        glyph.glyph = "\u{E721}"
        glyph.fontSize = 13
        glyph.width = 16
        glyph.foreground = Self.secondary
        glyph.horizontalAlignment = .left
        glyph.verticalAlignment = .center
        glyph.margin = Thickness(left: 12, top: 0, right: 0, bottom: 0)
        search.children.append(glyph)
        field.fontSize = 14
        field.foreground = Self.title
        field.verticalAlignment = .center
        field.minHeight = 0
        field.margin = Thickness(left: 28, top: 0, right: 8, bottom: 0)
        field.padding = Thickness(left: 8, top: 4, right: 4, bottom: 4)
        field.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        field.background = UI.clear
        field.isSpellCheckEnabled = false
        field.isTextPredictionEnabled = false
        for key in ["TextControlBackgroundFocused", "TextControlBackgroundPointerOver", "TextControlBorderBrushFocused",
                    "TextControlBorderBrushPointerOver", "TextControlBackground", "TextControlBorderBrush"] {
            _ = field.resources.insert(key, UI.clear)
        }
        _ = field.resources.insert("TextControlForegroundFocused", Self.title)
        _ = field.resources.insert("TextControlPlaceholderForeground", Self.secondary)
        _ = field.resources.insert("TextControlPlaceholderForegroundFocused", Self.secondary)
        field.textChanged.addHandler { [weak self] _, _ in self?.typed() }
        field.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args else { return }
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x28: self.move(by: 1)  // Down
            case 0x26: self.move(by: -1)  // Up
            case 0x0D: if self.shown.indices.contains(self.selected) { self.preview.pick(self.shown[self.selected].id) }  // Return
            case 0x1B: self.preview.close()  // Escape
            default: return
            }
            args.handled = true
        }
        search.children.append(field)
        root.children.append(search)

        let line = Border()
        line.background = Self.hairline
        root.children.append(line)
        try? Grid.setRow(line, 1)

        rowsPanel.padding = Thickness(left: 0, top: Double(FolderPreviewRows.listInset), right: 0, bottom: 0)
        scroll.content = rowsPanel
        scroll.verticalScrollBarVisibility = .auto
        scroll.horizontalScrollBarVisibility = .disabled
        root.children.append(scroll)
        try? Grid.setRow(scroll, 2)
        empty.horizontalAlignment = .center
        empty.verticalAlignment = .center
        empty.visibility = .collapsed
        root.children.append(empty)
        try? Grid.setRow(empty, 2)
    }

    func show(title: String, entries: [FolderPreviewList.Entry]) {
        self.entries = entries
        field.placeholderText = "Search \(title)…"
        field.text = ""
        root.height = Double(FolderPreviewList.height(rows: entries.count))
        filter(keepSelection: false)
        _ = try? scroll.changeView(nil, 0, nil, true)
    }

    /// After an archive: the rest stay, the selection on the same tab where it can.
    func replace(_ entries: [FolderPreviewList.Entry]) {
        self.entries = entries
        filter(keepSelection: true)
    }

    func focusSearch() {
        _ = try? field.focus(.programmatic)
    }

    private func typed() {
        preview.extended = true
        filter(keepSelection: false)
        _ = try? scroll.changeView(nil, 0, nil, true)
    }

    private func filter(keepSelection: Bool) {
        let previous = shown.indices.contains(selected) ? shown[selected].id : nil
        shown = FolderPreviewList.filter(entries, query: field.text)
        selected = keepSelection ? (shown.firstIndex { $0.id == previous } ?? min(selected, max(0, shown.count - 1))) : 0
        hoveredRow = nil
        rowsPanel.children.clear()
        rows = []
        let now = Date()
        for (i, entry) in shown.enumerated() {
            let row = makeRow(entry, index: i, now: now)
            rows.append(row)
            rowsPanel.children.append(row)
        }
        empty.visibility = shown.isEmpty ? .visible : .collapsed
        refreshFills()
    }

    private func move(by delta: Int) {
        guard !shown.isEmpty else { return }
        preview.extended = true
        selected = min(max(0, selected + delta), shown.count - 1)
        refreshFills()
        // Keep the row in sight.
        let pitch = Double(FolderPreviewRows.rowPitch), inset = Double(FolderPreviewRows.listInset)
        let top = Double(selected) * pitch, bottom = top + pitch + inset
        if top < scroll.verticalOffset {
            _ = try? scroll.changeView(nil, top, nil, true)
        } else if bottom > scroll.verticalOffset + scroll.viewportHeight {
            _ = try? scroll.changeView(nil, bottom - scroll.viewportHeight, nil, true)
        }
    }

    private func refreshFills() {
        for (i, row) in rows.enumerated() {
            row.background = i == selected || i == hoveredRow ? Self.rowFill : UI.clear
        }
    }

    /// 44 DIPs on a 45 DIP pitch, 4 in from each side: the favicon centred 20 from the card's
    /// edge, the title and how long ago it was used from 36, an unread tab's dot at the end.
    private func makeRow(_ entry: FolderPreviewList.Entry, index: Int, now: Date) -> Border {
        let row = Border()
        row.height = Double(FolderPreviewList.rowFill)
        row.margin = Thickness(left: 4, top: 0, right: 4, bottom: Double(FolderPreviewRows.rowPitch - FolderPreviewList.rowFill))
        row.cornerRadius = CornerRadius(topLeft: 4, topRight: 4, bottomRight: 4, bottomLeft: 4)
        let grid = Grid()
        let icon: FrameworkElement
        if let bitmap = favicons.bitmap(forKey: entry.iconKey, onDark: true) {
            icon = UI.image(bitmap, size: 16)
        } else {
            let globe = FontIcon()
            globe.glyph = WinGlyph.code("globe")
            globe.fontSize = 13
            globe.width = 16
            globe.height = 16
            globe.foreground = Self.secondary
            icon = globe
        }
        icon.horizontalAlignment = .left
        icon.verticalAlignment = .center
        icon.margin = Thickness(left: 8, top: 0, right: 0, bottom: 0)
        grid.children.append(icon)
        let text = StackPanel()
        text.verticalAlignment = .center
        text.margin = Thickness(left: 32, top: 0, right: entry.badged ? 24 : 10, bottom: 0)
        text.children.append(UI.text(entry.title, size: 13, color: Self.title))
        text.children.append(UI.text(FolderPreviewList.age(of: entry.lastVisit, now: now), size: 11, color: Self.secondary))
        grid.children.append(text)
        if entry.badged {
            let dot = WinUI.Ellipse()  // not GDI's Ellipse
            dot.width = 6
            dot.height = 6
            dot.fill = Self.title
            dot.horizontalAlignment = .right
            dot.verticalAlignment = .center
            dot.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
            grid.children.append(dot)
        }
        row.child = grid
        row.background = UI.clear
        let id = entry.id, url = entry.url
        let menu = MenuFlyout()
        menu.items.append(UI.menuItem("Copy Link") { [weak self] in self?.preview.copyLink(url) })
        menu.items.append(UI.menuItem("Open in Split View") { [weak self] in self?.preview.openInSplitView(id) })
        menu.items.append(UI.menuItem("Duplicate") { [weak self] in self?.preview.duplicate(id) })
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Archive") { [weak self] in self?.preview.archive(id) })
        row.contextFlyout = menu
        row.pointerEntered.addHandler { [weak self] _, _ in
            self?.hoveredRow = index
            self?.refreshFills()
        }
        row.pointerExited.addHandler { [weak self] _, _ in
            guard let self, self.hoveredRow == index else { return }
            self.hoveredRow = nil
            self.refreshFills()
        }
        row.pointerReleased.addHandler { [weak self, weak row] _, args in
            guard let self, let row, let args, let point = try? args.getCurrentPoint(row),
                  point.properties?.pointerUpdateKind == .leftButtonReleased else { return }
            args.handled = true
            self.preview.pick(id)
        }
        return row
    }
}
