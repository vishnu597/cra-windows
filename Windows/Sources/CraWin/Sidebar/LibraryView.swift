import CraCore
import Foundation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

/// What the Library asks of its window.
@MainActor
protocol LibraryActions: AnyObject {
    func showLibrary(_ page: LibraryPage)
    func closeLibrary()
    /// The tab back where it was closed from, selected, and the Library closes (the Mac's
    /// sidebarActions.restoreArchived).
    func restoreArchived(_ id: UUID)
    /// The keyboard back to the Library's search (Win32 focus into the XAML first).
    func focusLibrary()
    /// Arc's preview of `files[index]` over the window (Library ▸ Media's click on a tile).
    func previewMedia(_ files: [MediaLibrary.File], at index: Int)
}

/// Arc's Library as a mode of the sidebar (the Mac's LibraryView): the page rail on the left,
/// the page's search and its list by day on the right, the back arrow at the bottom of the rail.
/// The window widens the sidebar by LibraryLayout.extraWidth for it. Arc leaves it by the
/// shortcut, Escape or the arrow, and opens it again on the page last shown.
@MainActor
final class LibraryView {
    /// The pages Windows has, in the rail's order: no Easels (EaselCanvasView) or Boosts yet. A
    /// private window has no Spaces page (it shows only its own space).
    let pages: [LibraryPage]

    let root = Grid()
    private(set) var page: LibraryPage = .downloads
    private let store: SidebarStore
    private let history: DownloadHistory
    private let thumbnails: DownloadThumbnails
    private let favicons: Favicons
    private weak var actions: LibraryActions?
    /// The Spaces page (Manage Spaces…), over the search and list while it shows.
    private let spaces: SpacesManagerView?
    /// The search row and the list, which the Spaces page replaces.
    private let listColumn = Grid()

    private let rail = Border()
    private var railButtons: [(page: LibraryPage, button: Button, glyph: FontIcon, label: TextBlock)] = []
    private let backGlyph = FontIcon()
    private var back: Button!
    private let searchBox = Border()
    private let searchGlyph = FontIcon()
    private let search = TextBox()
    private let menuGlyph = FontIcon()
    private var menuButton: Button!
    /// The ⋯ button's menu, filled as it opens.
    private let pageMenu = MenuFlyout()
    private let rows = StackPanel()
    private let scroll = ScrollViewer()
    private let empty = StackPanel()
    private let emptyGlyph = FontIcon()
    private let emptyTitle = TextBlock()
    private let emptyDetail = TextBlock()
    private var palette = SidebarPalette(SpaceTheme.presets[0])
    /// Arc's card over the Media page until Show Media is pressed.
    private var mediaCard: Border?
    private let media = MediaScannerWin.shared
    /// The folders last read, so a redraw for another reason doesn't read them again.
    private var mediaScanned: [MediaLibrary.Folder]?
    private var query = ""
    /// What the rows were last built from: a store change that leaves it alone (a page's title)
    /// doesn't build them again.
    private var builtFrom: Int?

    init(store: SidebarStore, history: DownloadHistory, dispatcher: WinAppSDK.DispatcherQueue, favicons: Favicons = .shared,
         spaces: SpacesManagerView? = nil, actions: LibraryActions) {
        self.store = store
        self.spaces = spaces
        pages = spaces == nil ? [.media, .downloads, .archive] : [.media, .downloads, .spaces, .archive]
        self.history = history
        self.favicons = favicons
        self.actions = actions
        thumbnails = DownloadThumbnails(dispatcher: dispatcher)
        root.columnDefinitions.append(UI.column(UI.pixels(LibraryLayout.rail)))
        root.columnDefinitions.append(UI.column(UI.star))
        makeRail()
        makeList()
        if let spaces {
            spaces.root.visibility = .collapsed
            root.children.append(spaces.root)
            try? Grid.setColumn(spaces.root, 1)
        }
        root.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, !args.handled, Int32(truncatingIfNeeded: args.key.rawValue) == 0x1B else { return }
            args.handled = true
            self.actions?.closeLibrary()
        }
        // A click on the rail's or the list's background (nothing that takes focus) left the
        // keyboard with no element, so Escape reached nothing: the search takes it back.
        // Buttons, rows and the search handle their own taps.
        root.tapped.addHandler { [weak self] _, args in
            guard let self, let args, !args.handled else { return }
            args.handled = true
            self.actions?.focusLibrary()
        }
    }

    /// The page to show (its search starts empty).
    func show(_ page: LibraryPage) {
        guard page != self.page else { return }
        self.page = page
        query = ""
        search.text = ""
        search.placeholderText = page.searchPrompt
        builtFrom = nil
        let cards = page == .spaces && spaces != nil
        spaces?.root.visibility = cards ? .visible : .collapsed
        listColumn.visibility = cards ? .collapsed : .visible
    }

    /// The width the Spaces page's cards need with the rail, while it shows.
    var spacesWidth: Double? {
        page == .spaces ? spaces?.cardsWidth : nil
    }

    /// The search takes the keyboard (the window has moved Win32 focus into the XAML first).
    func focusSearch() {
        if page == .spaces, let spaces {
            spaces.focus()
        } else {
            _ = try? search.focus(.programmatic)
        }
    }

    /// Draws the page for the focused space's colours. Everything it reads from the store and
    /// the downloads is what a change redraws (BrowserWindow.refresh).
    func build(_ palette: SidebarPalette, dark: Bool) {
        let archive = store.archive
        let entries = history.entries
        // Running, failed and cancelled downloads too (#245; the PC test found the page without
        // a running one): their progress lines are part of what redraws it.
        let listed = page == .downloads ? history.library(query: query) : []
        let revision = thumbnails.revision
        var key = Hasher()
        key.combine(page)
        key.combine(query)
        key.combine(dark)
        key.combine(revision)
        key.combine(archive.map(\.id))
        key.combine(archive.map(\.item.displayTitle))
        key.combine(entries.map(\.id))
        key.combine(listed.map { "\($0.id)|\($0.name)|\($0.subtitle(now: Date()))" })
        key.combine(Calendar.current.startOfDay(for: Date()))
        if page == .media {
            key.combine(store.settings.mediaLibraryEnabled)
            key.combine(store.settings.mediaFolders.map(\.rawValue))
            key.combine(store.settings.mediaHidden)
            key.combine(media.files.map(\.path))
            key.combine(media.revision)
        }
        let built = key.finalize()
        self.palette = palette
        root.requestedTheme = dark ? .dark : .light
        applyColors(dark: dark)
        // The cards read the spaces, their tabs and colours: drawn on every change they watch.
        if page == .spaces, let spaces {
            builtFrom = nil
            return spaces.build(dark: dark)
        }
        guard built != builtFrom else { return }
        // Read again when the page shows or its folders change; the scan is off the UI thread.
        if page == .media, store.settings.mediaLibraryEnabled, builtFrom == nil || mediaScanned != store.settings.mediaFolders {
            mediaScanned = store.settings.mediaFolders
            media.rescan(store.settings.mediaFolders)
        }
        builtFrom = built
        rows.children.clear()
        mediaCard?.visibility = .collapsed
        switch page {
        case .downloads:
            let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
            let sections = LibraryList.downloads(listed)
            for section in sections {
                addHeader(section.title)
                for row in section.items { addDownload(row) }
            }
            showEmpty(sections.isEmpty, LibraryList.empty(.downloads, hasAny: !history.live.isEmpty || entries.contains { exists($0.path) }))
        case .archive:
            let sections = LibraryList.archive(archive, matching: query)
            for section in sections {
                addHeader(section.title)
                for item in section.items { addArchived(item) }
            }
            showEmpty(sections.isEmpty, LibraryList.empty(.archive, hasAny: !archive.isEmpty))
        case .media:
            guard store.settings.mediaLibraryEnabled else {
                showEmpty(false, LibraryList.empty(.media, hasAny: false))
                scroll.visibility = .collapsed
                showMediaCard(dark: dark)
                break
            }
            let files = MediaLibrary.shown(media.files, query: query, hidden: Set(store.settings.mediaHidden))
            for pair in MediaLibrary.rows(files) { addMediaRow(pair, in: files, dark: dark) }
            showEmpty(files.isEmpty, LibraryList.empty(.media, hasAny: !media.files.isEmpty))
        case .easels, .boosts, .spaces:
            showEmpty(true, LibraryList.Empty(symbol: page.symbol, title: "Not on Windows yet", detail: nil))
        }
    }

    // MARK: Rail

    private func makeRail() {
        let column = Grid()
        for height in [UI.star, UI.auto, UI.star, UI.auto] { column.rowDefinitions.append(UI.row(height)) }
        let group = StackPanel()
        group.spacing = 20
        group.horizontalAlignment = .center
        for page in pages {
            let glyph = FontIcon()
            glyph.glyph = WinGlyph.code(page.symbol)
            glyph.fontSize = 17
            let label = UI.text(page.title, size: 12, trimmed: false)
            label.fontWeight = UWP.FontWeight(weight: 600)
            label.textAlignment = .center
            label.textWrapping = .wrap
            let stack = StackPanel()
            stack.spacing = 9
            stack.horizontalAlignment = .center
            stack.verticalAlignment = .center
            stack.children.append(glyph)
            stack.children.append(label)
            let button = UI.button(stack, padding: Thickness(left: 4, top: 4, right: 4, bottom: 4)) { [weak self] in
                self?.actions?.showLibrary(page)
            }
            button.width = 97
            button.height = 80
            button.cornerRadius = CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
            try? AutomationProperties.setName(button, page.title)
            group.children.append(button)
            railButtons.append((page, button, glyph, label))
        }
        column.children.append(group)
        try? Grid.setRow(group, 1)

        backGlyph.glyph = WinGlyph.code("arrow.left")
        backGlyph.fontSize = 15
        back = UI.button(backGlyph, padding: Thickness(left: 8, top: 8, right: 8, bottom: 8)) { [weak self] in
            self?.actions?.closeLibrary()
        }
        back.horizontalAlignment = .left
        back.margin = Thickness(left: 8, top: 0, right: 0, bottom: 8)
        ArcTip.set(back, "Exit the Library (Esc)")
        try? AutomationProperties.setName(back, "Exit the Library")
        column.children.append(back)
        try? Grid.setRow(back, 3)

        rail.child = column
        rail.borderThickness = Thickness(left: 0, top: 0, right: 1, bottom: 0)
        root.children.append(rail)
    }

    // MARK: List

    private func makeList() {
        let column = listColumn
        column.rowDefinitions.append(UI.row(UI.auto))
        column.rowDefinitions.append(UI.row(UI.star))

        // The search field and the ⋯ button, 10 DIPs down (Arc's HStack(spacing: 4)).
        let top = Grid()
        top.columnDefinitions.append(UI.column(UI.star))
        top.columnDefinitions.append(UI.column(UI.pixels(36)))
        top.columnSpacing = 4
        top.margin = Thickness(left: 7, top: 10, right: 8, bottom: 0)
        searchGlyph.glyph = WinGlyph.code("magnifyingglass")
        searchGlyph.fontSize = 13
        searchGlyph.margin = Thickness(left: 12, top: 0, right: 0, bottom: 0)
        searchGlyph.verticalAlignment = .center
        search.fontSize = 14
        search.placeholderText = page.searchPrompt
        search.verticalAlignment = .center
        search.minHeight = 0
        search.padding = Thickness(left: 6, top: 6, right: 8, bottom: 6)
        search.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        search.background = UI.clear
        search.isSpellCheckEnabled = false
        search.isTextPredictionEnabled = false
        for key in ["TextControlBackgroundFocused", "TextControlBackgroundPointerOver", "TextControlBorderBrushFocused",
                    "TextControlBorderBrushPointerOver", "TextControlBackground", "TextControlBorderBrush"] {
            _ = search.resources.insert(key, UI.clear)
        }
        search.textChanged.addHandler { [weak self] _, _ in
            guard let self, self.search.text != self.query else { return }
            self.query = self.search.text
            self.build(self.palette, dark: self.palette.isDark)
        }
        search.previewKeyDown.addHandler { [weak self] _, args in
            guard let self, let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x1B else { return }
            args.handled = true
            self.actions?.closeLibrary()
        }
        let field = Grid()
        field.columnDefinitions.append(UI.column(UI.auto))
        field.columnDefinitions.append(UI.column(UI.star))
        field.children.append(searchGlyph)
        field.children.append(search)
        try? Grid.setColumn(search, 1)
        searchBox.child = field
        searchBox.height = 36
        searchBox.cornerRadius = CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
        top.children.append(searchBox)

        menuGlyph.glyph = WinGlyph.code("ellipsis")
        menuGlyph.fontSize = 14
        menuButton = UI.button(menuGlyph, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) {}
        menuButton.flyout = pageMenu
        pageMenu.opening.addHandler { [weak self] _, _ in self?.fillMenu() }
        menuButton.width = 36
        menuButton.height = 36
        menuButton.cornerRadius = CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
        try? AutomationProperties.setName(menuButton, "More")
        top.children.append(menuButton)
        try? Grid.setColumn(menuButton, 1)
        column.children.append(top)

        rows.orientation = .vertical
        rows.padding = Thickness(left: 0, top: 0, right: 0, bottom: 12)
        scroll.content = rows
        column.children.append(scroll)
        try? Grid.setRow(scroll, 1)

        // 260 DIPs down from the top (46 under the search row): the glyph, the title, the detail.
        emptyGlyph.fontSize = 30
        emptyTitle.fontSize = 17
        emptyTitle.fontWeight = UWP.FontWeight(weight: 600)
        emptyTitle.textAlignment = .center
        emptyDetail.fontSize = 14
        emptyDetail.textAlignment = .center
        emptyDetail.textWrapping = .wrap
        empty.spacing = 8
        empty.margin = Thickness(left: 16, top: 260 - 46 - 46, right: 16, bottom: 0)
        empty.children.append(emptyGlyph)
        empty.children.append(emptyTitle)
        empty.children.append(emptyDetail)
        column.children.append(empty)
        try? Grid.setRow(empty, 1)

        root.children.append(column)
        try? Grid.setColumn(column, 1)
    }

    private func showEmpty(_ isEmpty: Bool, _ state: LibraryList.Empty) {
        empty.visibility = isEmpty ? .visible : .collapsed
        scroll.visibility = isEmpty ? .collapsed : .visible
        emptyGlyph.glyph = WinGlyph.code(state.symbol)
        emptyTitle.text = state.title
        emptyDetail.text = state.detail ?? ""
        emptyDetail.visibility = state.detail == nil ? .collapsed : .visible
    }

    private func applyColors(dark: Bool) {
        let ink: UInt8 = dark ? 255 : 0
        rail.background = UI.brush(ink, ink, ink, alpha: 8)
        rail.borderBrush = UI.brush(ink, ink, ink, alpha: 23)
        for b in railButtons {
            let selected = b.page == page
            b.button.background = selected ? UI.brush(ink, ink, ink, alpha: 18) : UI.clear
            b.glyph.foreground = selected ? palette.text : palette.secondaryText
            b.label.foreground = UI.brush(ink, ink, ink, alpha: selected ? 209 : 153)
            b.glyph.glyph = WinGlyph.code(selected ? b.page.selectedSymbol : b.page.symbol)
        }
        backGlyph.foreground = palette.secondaryText
        searchBox.background = UI.brush(ink, ink, ink, alpha: 20)
        searchGlyph.foreground = UI.brush(ink, ink, ink, alpha: 128)
        search.foreground = palette.text
        menuButton.background = UI.brush(ink, ink, ink, alpha: 13)
        menuGlyph.foreground = UI.brush(ink, ink, ink, alpha: 179)
        emptyGlyph.foreground = UI.brush(ink, ink, ink, alpha: 115)
        emptyTitle.foreground = UI.brush(ink, ink, ink, alpha: 230)
        emptyDetail.foreground = UI.brush(ink, ink, ink, alpha: 179)
    }

    /// The ⋯ button's menu (Arc's Filter button; Cra's holds the page's actions).
    private func fillMenu() {
        pageMenu.items.clear()
        switch page {
        case .downloads:
            pageMenu.items.append(UI.menuItem("Open Downloads Folder") { [weak self] in
                // The focused space's profile, as the Mac's opens the Library's profile's folder.
                guard let store = self?.store else { return }
                let sid = store.focusedSpaceID
                let profile = store.isIncognito(space: sid) ? nil : store.spaces[sid]?.profileID
                Shell.openDownloadsFolder(store.settings.downloadLocation(profileID: profile))
            })
        case .archive:
            let clear = UI.menuItem("Clear Archive") { [weak self] in self?.store.clearArchive() }
            clear.isEnabled = !store.archive.isEmpty
            pageMenu.items.append(clear)
        case .media:
            // Arc's right-click on the Library button: "Show media", each folder ticked when shown.
            let header = UI.menuItem("Show media") {}
            header.isEnabled = false
            pageMenu.items.append(header)
            for folder in MediaLibrary.Folder.allCases {
                let entry = ToggleMenuFlyoutItem()
                entry.text = folder.title
                entry.isChecked = store.settings.mediaFolders.contains(folder)
                entry.click.addHandler { [weak self] _, _ in
                    guard let self else { return }
                    self.store.settings.mediaFolders = MediaLibrary.toggled(folder, in: self.store.settings.mediaFolders)
                }
                pageMenu.items.append(entry)
            }
            if store.settings.mediaLibraryEnabled {
                pageMenu.items.append(MenuFlyoutSeparator())
                pageMenu.items.append(UI.menuItem("Hide Media") { [weak self] in self?.store.settings.mediaLibraryEnabled = false })
            }
        case .easels, .spaces, .boosts:
            break
        }
    }

    // MARK: Media

    /// Arc's card over the Media page until it is turned on (the Mac's MediaOptInCard): its glyph,
    /// "Your Media in the Library", what it does, Show Media and the privacy line, 222 DIPs wide.
    private func showMediaCard(dark: Bool) {
        let card = mediaCard ?? makeMediaCard()
        card.background = dark ? UI.brush(46, 46, 46) : UI.brush(255, 255, 255)
        card.requestedTheme = dark ? .dark : .light
        card.visibility = .visible
    }

    private func makeMediaCard() -> Border {
        let stack = StackPanel()
        stack.spacing = 8
        let glyph = FontIcon()
        glyph.glyph = WinGlyph.code("photo.on.rectangle")
        glyph.fontSize = 28
        glyph.foreground = UI.brush(140, 120, 237)
        glyph.margin = Thickness(left: 0, top: 4, right: 0, bottom: 0)
        stack.children.append(glyph)
        let title = UI.text(MediaLibrary.OptIn.title, size: 13)
        title.fontWeight = UWP.FontWeight(weight: 600)
        title.horizontalAlignment = .center
        stack.children.append(title)
        let detail = UI.text(MediaLibrary.OptIn.detail, size: 11.5)
        detail.textWrapping = .wrap
        detail.textAlignment = .center
        detail.opacity = 0.8
        stack.children.append(detail)
        let label = UI.text(MediaLibrary.OptIn.button, size: 13, color: UI.brush(255, 255, 255))
        label.fontWeight = UWP.FontWeight(weight: 500)
        label.horizontalAlignment = .center
        let button = UI.button(label, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
            self?.store.settings.mediaLibraryEnabled = true
        }
        button.height = 32
        button.horizontalAlignment = .stretch
        button.cornerRadius = CornerRadius(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        // Arc's pink-to-blue button.
        let fill = LinearGradientBrush()
        fill.startPoint = WindowsFoundation.Point(x: 0, y: 0.5)
        fill.endPoint = WindowsFoundation.Point(x: 1, y: 0.5)
        for (offset, color) in [(0.0, UWP.Color(a: 255, r: 217, g: 140, b: 204)), (1.0, UWP.Color(a: 255, r: 102, g: 107, b: 242))] {
            let stop = GradientStop()
            stop.offset = offset
            stop.color = color
            fill.gradientStops.append(stop)
        }
        button.background = fill
        button.margin = Thickness(left: 0, top: 4, right: 0, bottom: 0)
        stack.children.append(button)
        let privacy = StackPanel()
        privacy.orientation = .horizontal
        privacy.spacing = 4
        let lock = FontIcon()
        lock.glyph = WinGlyph.code("lock.fill")
        lock.fontSize = 8
        lock.verticalAlignment = .top
        lock.margin = Thickness(left: 0, top: 3, right: 0, bottom: 0)
        privacy.children.append(lock)
        let line = UI.text(MediaLibrary.OptIn.privacy, size: 10)
        line.textWrapping = .wrap
        line.maxWidth = 176
        privacy.children.append(line)
        privacy.opacity = 0.6
        stack.children.append(privacy)
        let card = Border()
        card.child = stack
        card.width = 222
        card.padding = Thickness(left: 16, top: 16, right: 16, bottom: 16)
        card.cornerRadius = CornerRadius(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
        card.horizontalAlignment = .center
        card.verticalAlignment = .top
        card.margin = Thickness(left: 0, top: 60, right: 0, bottom: 0)
        listColumn.children.append(card)
        try? Grid.setRow(card, 1)
        mediaCard = card
        return card
    }

    /// One row of Arc's grid: up to two tiles, the picture fitted in each.
    private func addMediaRow(_ files: [MediaLibrary.File], in shown: [MediaLibrary.File], dark: Bool) {
        let m = MediaGridWin.self
        let row = Grid()
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnSpacing = m.gap
        row.margin = Thickness(left: m.inset, top: 0, right: m.trailing, bottom: m.rowGap)
        let ink: UInt8 = dark ? 255 : 0
        for (i, file) in files.enumerated() {
            let picture = Border()
            picture.background = UI.brush(255, 255, 255)
            picture.padding = Thickness(left: m.frame, top: m.frame, right: m.frame, bottom: m.frame)
            picture.horizontalAlignment = .center
            picture.verticalAlignment = .center
            if let image = media.thumbnail(file) {
                let view = WinUI.Image()
                view.source = image
                view.stretch = .uniform
                view.maxWidth = m.tile - 2 * m.padding - 2 * m.frame
                view.maxHeight = m.tile - 2 * m.padding - 2 * m.frame
                picture.child = view
            } else {
                picture.width = 96
                picture.height = 72
                picture.background = UI.brush(ink, ink, ink, alpha: 15)
            }
            let tile = Grid()
            tile.children.append(picture)
            if MediaLibrary.isVideo(file.path) {
                // Arc marks a video with a white ▶ over its picture.
                let play = FontIcon()
                play.glyph = WinGlyph.code("play.fill")
                play.fontSize = 22
                play.foreground = UI.brush(255, 255, 255)
                play.horizontalAlignment = .center
                play.verticalAlignment = .center
                tile.children.append(play)
            }
            let menu = MenuFlyout()
            let video = MediaLibrary.isVideo(file.path)
            for action in MediaLibrary.windowsActions {
                if action.startsGroup { menu.items.append(MenuFlyoutSeparator()) }
                menu.items.append(UI.menuItem(action.windowsTitle(isVideo: video)) { [weak self] in
                    guard let self else { return }
                    switch action {
                    case .copy: MediaClipboard.copy(file.path)
                    case .showInFinder: Shell.showInFolder(file.path)
                    case .hide:
                        if !self.store.settings.mediaHidden.contains(file.path) { self.store.settings.mediaHidden.append(file.path) }
                    case .sendMessage, .airDrop: break
                    }
                })
            }
            // A click shows Arc's preview over the window, from there through the grid's order;
            // a drag hands the file out (FileDragOut).
            let button = UI.button(tile, padding: Thickness(left: m.padding, top: m.padding, right: m.padding, bottom: m.padding)) { [weak self] in
                FileDragOut.pressed(path: file.path) { self?.actions?.previewMedia(shown, at: shown.firstIndex(of: file) ?? 0) }
            }
            button.height = m.tile
            button.horizontalAlignment = .stretch
            button.horizontalContentAlignment = .center
            button.verticalContentAlignment = .center
            button.cornerRadius = CornerRadius(topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10)
            button.background = UI.brush(ink, ink, ink, alpha: 10)
            button.contextFlyout = menu
            ArcTip.set(button, file.name)
            try? AutomationProperties.setName(button, file.name)
            row.children.append(button)
            try? Grid.setColumn(button, Int32(i))
        }
        rows.children.append(row)
    }

    // MARK: Rows

    private func addHeader(_ title: String) {
        let label = UI.text(title, size: 13, color: palette.secondaryText)
        label.fontWeight = UWP.FontWeight(weight: 600)
        // 11 DIPs in, 18 above, 6 below: a 40 DIP header.
        label.margin = Thickness(left: 11, top: 18, right: 8, bottom: 6)
        rows.children.append(label)
    }

    private func addArchived(_ entry: ArchivedItem) {
        let id = entry.id
        let url = entry.item.tab?.url ?? ""
        let tile = Border()
        tile.width = 24
        tile.height = 24
        tile.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
        tile.background = palette.tile
        if let bitmap = favicons.bitmap(forKey: entry.item.tab?.iconKey, onDark: palette.isDark) {
            let image = UI.image(bitmap, size: 16)
            image.horizontalAlignment = .center
            image.verticalAlignment = .center
            tile.child = image
        }
        let menu = MenuFlyout()
        menu.items.append(UI.menuItem("Restore") { [weak self] in self?.actions?.restoreArchived(id) })
        menu.items.append(UI.menuItem("Copy Link") { _ = WinShell.copy(url) })
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Remove from Archive") { [weak self] in self?.store.removeFromArchive(id) })
        let row = addRow(tile: tile, tileInset: 9, title: entry.item.displayTitle,
                         detail: SuggestionEngine.humanURL(url), menu: menu) { [weak self] in
            self?.actions?.restoreArchived(id)
        }
        if !url.isEmpty { ArcTip.set(row, url, placement: .cursor) }
    }

    /// A download's row: a finished file's preview (or its type's icon while it runs), its name
    /// and DownloadList's line (progress, "Cancelled", or size and time).
    private func addDownload(_ row: DownloadHistory.Listed) {
        let picture: WriteableBitmap?
        let path: String?
        switch row {
        case .finished(let entry):
            picture = thumbnails.thumbnail(for: entry.path)
            path = entry.path
        case .live(let live):
            picture = thumbnails.typeIcon(for: live.name)
            path = nil
        }
        let tile: FrameworkElement
        if let picture {
            tile = UI.image(picture, size: 32)
        } else {
            let box = Border()
            box.width = 32
            box.height = 32
            box.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
            box.background = palette.tile
            tile = box
        }
        // Arc's download menu (DownloadMenu): Pause, Resume and Cancel while it runs; Open, Copy,
        // Show in Folder, Hide, Move to Recycle Bin once done. Refilled as it opens.
        let menu = MenuFlyout()
        let history = self.history
        DownloadRowMenu.fill(menu, for: row, history: history)
        menu.opening.addHandler { [weak menu] _, _ in
            guard let menu else { return }
            let now = history.library(query: "").first { $0.id == row.id } ?? row
            DownloadRowMenu.fill(menu, for: now, history: history)
        }
        let title = path.map(LibraryList.fileName) ?? row.name
        // A click opens the file; a finished one drags out as the file itself (the Mac's
        // LibraryItemCell; a file gone from the disk doesn't start one).
        addRow(tile: tile, tileInset: 5, title: title, detail: row.subtitle(now: Date()), menu: menu) {
            FileDragOut.pressed(path: path) { if let path { Shell.open(path) } }
        }
    }

    /// A 52 DIP card inside 4 × 2 DIPs of padding: the tile, then the title over the detail; the
    /// space's hover fill under the pointer.
    @discardableResult
    private func addRow(tile: FrameworkElement, tileInset: Double, title: String, detail: String, menu: MenuFlyout, _ action: @escaping @MainActor () -> Void) -> Button {
        let content = Grid()
        content.columnDefinitions.append(UI.column(UI.auto))
        content.columnDefinitions.append(UI.column(UI.star))
        content.columnSpacing = 10
        tile.verticalAlignment = .center
        tile.margin = Thickness(left: tileInset, top: 0, right: 0, bottom: 0)
        content.children.append(tile)
        let text = StackPanel()
        text.spacing = 1
        text.verticalAlignment = .center
        text.margin = Thickness(left: 0, top: 0, right: 8, bottom: 0)
        text.children.append(UI.text(title.isEmpty ? "Untitled" : title, size: 14, color: palette.text))
        text.children.append(UI.text(detail, size: 12, color: palette.secondaryText))
        content.children.append(text)
        try? Grid.setColumn(text, 1)
        let row = UI.button(content, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0), action)
        row.height = LibraryLayout.rowHeight - 4
        row.margin = Thickness(left: 4, top: 2, right: 4, bottom: 2)
        row.horizontalAlignment = .stretch
        row.horizontalContentAlignment = .stretch
        row.cornerRadius = CornerRadius(topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10)
        row.contextFlyout = menu
        try? AutomationProperties.setName(row, title)
        rows.children.append(row)
        return row
    }
}
