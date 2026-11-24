import CraCore
import Foundation
import Observation
import UWP
import WinAppSDK
import WinSDK
import WindowsFoundation
import WinUI

/// What the sidebar asks of its window: things that touch pages, not only the store.
@MainActor
protocol SidebarActions: AnyObject {
    /// ✕ on a row: Today tabs are archived, pinned tabs and favorites unload (MainWindowController.closeTab).
    func closeTab(_ id: UUID)
    /// "+ New Tab": the command bar, making a new tab.
    func beginNewTab()
    /// A split row's "Add Tab…": an empty pane after its panes, the command bar asking for its page.
    func addPane(toSplit id: UUID)
    /// A pane's "Close": the pane's tab goes and the split keeps the others.
    func closeSplitPane(_ id: UUID)
    /// Set Profile ▸ New Profile…: Create a new Profile, with this space ticked.
    func newProfile(forSpace id: UUID)
    /// A rename field is up: it takes the keyboard (Win32 focus into the XAML first).
    func focusRenameField(_ field: TextBox)
    /// A rename ended (Return, Escape or a click elsewhere): the keyboard goes back to the page.
    func renameEnded()
    /// The open tab's "Add Split View": an empty pane beside it, the command bar asking for its page.
    func addSplitView()
    /// Another tab's "Open in Split View": it joins the open tab in a split.
    func openInSplitView(_ id: UUID)
    /// Mutes or unmutes the tab and its page (the speaker on its row, its menu, Mute / Unmute Tab).
    func toggleMute(_ id: UUID)
    /// Back to Pinned Page: the pinned tab returns to its pinned page.
    func resetPinnedTab(_ id: UUID)
    /// Edit Pinned Page ▸ Edit…: the Edit Pinned URL card for a pinned tab or favorite.
    func editPinnedURL(_ id: UUID)
    /// Ctrl-click on a pinned tab's favicon away from its page: the page moves to a new Today
    /// tab and the pinned tab goes home (Separate From Pinned Tab).
    func separatePinnedTab(_ id: UUID)
    /// Manage Spaces…: the Library's Spaces page.
    func showLibrary(_ page: LibraryPage)
    /// Delete Space…: Arc asks first.
    func confirmDeleteSpace(_ id: UUID)
    /// A command by its id (KeyBindingDefaults), as the command bar runs it.
    func runCommand(_ id: String)
    /// A sidebar tab dragged off the sidebar, over the page: whether the panes offer a split at
    /// the pointer (the window shows it). `before`: the tab open before the press.
    func splitDragMoved(tab id: UUID, before: UUID?) -> Bool
    /// That drag left the page or ended; `drop` makes the split it offered.
    func splitDragEnded(tab id: UUID, drop: Bool)
}

/// The row or space header whose name is being edited (the Mac's SidebarUIState.renamingID and
/// renamingSpaceID). Observed, so setting it draws the sidebar again with a field in its place.
@Observable
@MainActor
final class SidebarRenaming {
    var itemID: UUID?
    var spaceID: UUID?
}

/// Arc's sidebar on the shared SidebarStore: favorites as tiles, the space's name, its pinned
/// tabs and folders, a New Tab row, its Today tabs, and the spaces along the bottom. Rebuilt
/// from the store on every change it read (BrowserWindow.refresh observes `build`).
@MainActor
final class SidebarView {
    let root = Grid()
    let favorites = Grid()
    private let header = Grid()
    let list = StackPanel()
    let scroll = ScrollViewer()
    let spacesBar = StackPanel()
    /// The downloads button on the left (Arc's Library button) over the same cell as the spaces,
    /// so they stay centred whatever the button shows.
    let footer = Grid()
    /// Arc's + at the dock's right end: a new space.
    let plusButton = UI.button("+") {}
    /// The dock's cells as drawn, the space under the pointer, and Shift + wheel's running total.
    var dockCells: [SidebarDockCell] = []
    var dockHovered: UUID?
    var wheel = WheelSpaceSwitch()
    /// Arc's "+" past the last space, the sideways wheel's pull that brings it out, and the timer
    /// that looks for the pull's end (NewSpacePlus.swift).
    let newSpacePlus = NewSpacePlusView()
    var newSpacePull = NewSpaceWheelPull()
    var newSpaceLiftTimer: WinAppSDK.DispatcherQueueTimer?
    /// The space header's name button, where Change Space Icon… points its picker, and the open picker.
    var headerTitle: FrameworkElement?
    var iconPicker: SpaceIconPickerView?
    var styleEditor: SpaceStyleEditorView?
    var creationMenu: MenuFlyout?
    /// Arc's Create a Space page while it is up (SpaceCreationPage.swift), over the space's part.
    var creationPage: SpaceCreationPageView?
    /// Where the page goes: over the favorites, the header and the list, empty while it is down.
    private let creationHost = Border()
    let store: SidebarStore
    /// The window it draws: its space, its selected tab (SidebarStore.WindowSession).
    let windowID: UUID
    let favicons: Favicons
    weak var actions: SidebarActions?
    private(set) var palette = SidebarPalette(SpaceTheme.presets[0])
    /// The window's active look (HostWindow.activeLook): a one-colour or editor-made space goes
    /// to Arc's flat inactive grey under its colour while another app or window is in front.
    var windowActive = true
    /// Controls a handler reaches weakly: a WinRT control made in Swift is only a wrapper, freed
    /// (and its weak references nil) once Swift lets go of it, however long XAML shows it.
    private var kept: [AnyObject] = []
    /// Arc badges the tab a Peek came from with the peeked page's favicon (modalIcon), at the
    /// row's end. Set by the browser window, which builds the sidebar again.
    var peekBadge: (tabID: UUID, iconKey: String?)?
    /// The tabs whose page makes sound, or did in the last 2 s (the Mac's audibleTabIDs): their
    /// row shows the speaker and Clear keeps them. Set by the browser window.
    var audibleTabIDs: Set<UUID> = []
    /// A press on the favicon of a pinned tab away from its page (Arc's icon region), and when.
    private var iconPress: (id: UUID, at: UInt64)?
    /// The last click on a tab row and whether it went back home (PinnedIconClick: a double-click
    /// on the icon goes back once, then neither clicks again nor renames, #345).
    private var lastTabClick: (id: UUID, at: UInt64, wentBack: Bool)?
    /// The model identity survives a redraw that replaces a row between mouse presses.
    var clickTracker = SidebarClick()
    private var rowClickCount = 1
    /// What is being renamed (Rename…, Rename Space…, a new folder, a double-click).
    let renaming = SidebarRenaming()

    // MARK: Drag and drop (SidebarDrag.swift)

    /// Over everything else, never hit: the insertion line, a combine's outline, the dragged row's
    /// stand-in by the pointer.
    let overlay = Canvas()
    /// "Add to Favorites" where the tiles go while a tab is dragged and the space has none.
    let favoritesCard = Border()
    /// The item rows as drawn, top to bottom, and the line between pinned and Today.
    var rowMeta: [SidebarRowMeta] = []
    var divider: FrameworkElement?
    /// The favorite tiles and the space icons as drawn.
    var favoriteTiles: [(element: FrameworkElement, id: UUID)] = []
    var spaceCells: [(element: FrameworkElement, id: UUID)] = []
    /// The pointer in the XAML's coordinates (DIPs from the island's top left), and the mouse
    /// held for a drag so no page sees it: set by the window.
    var pointer: () -> (x: Double, y: Double)? = { nil }
    var captureMouse: () -> Void = {}
    let drag = SidebarDragState()

    /// Emoji a new space picks from, in turn.
    private static let spaceEmoji = ["🌱", "💼", "🎮", "📚", "🎨", "🏠", "✈️", "🧪"]
    /// The sidebar's content width before its first layout (the default 328 DIPs, WindowPrefs, less 10 each side).
    private static let restingWidth = 308.0
    /// The close button's square and the unread dot centred where it shows (Arc 1.171, #139).
    private static let closeSize = 24.0, unreadDotSize = 6.0
    /// Each folder's row as drawn, for Change Icon…'s picker to hang under.
    private var folderRows: [UUID: FrameworkElement] = [:]
    func folderRow(_ id: UUID) -> FrameworkElement? { folderRows[id] }
    /// Dia's pill back to the open tab while its row is scrolled away (SidebarJumpPill.swift).
    let jumpPill = SidebarJumpPill()
    /// The favorites', header's and list's shift while a space switch slides (SpaceSwitchSlide).
    private let slideShifts = [TranslateTransform(), TranslateTransform(), TranslateTransform()]
    /// Arc's folder preview: a closed folder's tabs on a card beside the sidebar.
    private(set) lazy var folderPreview = FolderPreview(sidebar: self)
    /// The favorites' columns as drawn, nil with none.
    private var favoritesColumns: Int?

    init(store: SidebarStore, windowID: UUID, actions: SidebarActions, favicons: Favicons = .shared) {
        self.store = store
        self.windowID = windowID
        self.favicons = favicons
        self.actions = actions
        for height in [UI.auto, UI.auto, UI.star, UI.auto] { root.rowDefinitions.append(UI.row(height)) }
        favorites.margin = Thickness(left: 0, top: 0, right: 0, bottom: 8)
        favorites.columnSpacing = Double(FavoritesLayout.gap)
        favorites.rowSpacing = Double(FavoritesLayout.gap)
        header.margin = Thickness(left: 0, top: 4, right: 0, bottom: 4)
        list.orientation = .vertical
        list.spacing = 1
        scroll.content = list
        spacesBar.orientation = .horizontal
        spacesBar.spacing = 0
        spacesBar.horizontalAlignment = .center
        footer.margin = Thickness(left: 0, top: 8, right: 0, bottom: 0)
        // A clear fill so a right-click past the dock's icons reaches its Spaces menu.
        footer.background = UI.clear
        footer.children.append(spacesBar)
        plusButton.horizontalAlignment = .right
        plusButton.verticalAlignment = .center
        // Arc 1.172.1: + opens the creation menu, with no tooltip.
        plusButton.click.addHandler { [weak self] _, _ in self?.showCreationMenu() }
        try? AutomationProperties.setName(plusButton, "New")
        footer.children.append(plusButton)
        // A narrower or wider sidebar can squeeze the dock into dots or give them room again.
        footer.sizeChanged.addHandler { [weak self] _, _ in self?.refreshDock() }
        let parts: [FrameworkElement] = [favorites, header, scroll, footer]
        for (i, part) in parts.enumerated() {
            root.children.append(part)
            try? Grid.setRow(part, Int32(i))
        }
        // The space's own part slides on a switch (slideSpace); the dock stays put, as on the Mac.
        for (part, shift) in zip([favorites, header, scroll] as [FrameworkElement], slideShifts) { part.renderTransform = shift }
        root.children.append(jumpPill.body)
        try? Grid.setRow(jumpPill.body, 2)
        try? Canvas.setZIndex(jumpPill.body, 50)
        jumpPill.onClick = { [weak self] in self?.jumpToSelectedRow() }
        scroll.viewChanged.addHandler { [weak self] _, _ in self?.updateJumpPill() }
        scroll.sizeChanged.addHandler { [weak self] _, _ in self?.updateJumpPill() }
        creationHost.visibility = .collapsed
        root.children.append(creationHost)
        root.children.append(newSpacePlus.root)
        try? Grid.setRowSpan(newSpacePlus.root, 4)
        try? Canvas.setZIndex(newSpacePlus.root, 90)
        try? Grid.setRowSpan(creationHost, 3)
        makeDragChrome()
        makeLinkDropTarget()
        root.sizeChanged.addHandler { [weak self] _, _ in self?.favoritesWidthChanged() }
        // A mouse's back and forward buttons over the sidebar switch spaces (Arc's
        // SidebarView.otherMouseUp:, #233); over a page they stay Chromium's. A clear fill so the
        // sidebar's empty space takes the press too.
        root.background = UI.clear
        root.pointerReleased.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(nil), let properties = point.properties else { return }
            let kind = properties.pointerUpdateKind
            let xButton = kind == .xbutton1Released ? 1 : kind == .xbutton2Released ? 2 : 0
            guard let offset = MouseButtonSpaceSwitch.buttonNumber(windowsXButton: xButton).flatMap(MouseButtonSpaceSwitch.offset(buttonNumber:))
            else { return }
            args.handled = true
            self.store.focusSpace(offset: offset, window: self.windowID)
        }
        // Shift + wheel or a sideways wheel switches spaces (#93); a plain wheel scrolls the list.
        root.pointerWheelChanged.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(nil), let properties = point.properties else { return }
            if self.wheelOverSidebar(delta: Int(properties.mouseWheelDelta), horizontal: properties.isHorizontalMouseWheel) {
                args.handled = true
            }
        }
        root.pointerExited.addHandler { [weak self] _, _ in self?.hoverDock(nil) }
    }

    /// Draws the focused space. Everything it reads from the store is what a change redraws.
    func build() {
        let space = store.focusedSpace(window: windowID)
        // An Auto theme shows its light or dark half by View ▸ Appearance (WinAppearance.forcedDark,
        // set from this setting): reading it here redraws the sidebar when it changes.
        _ = store.settings.websiteAppearance
        palette = SidebarPalette(space.theme, active: windowActive)
        kept = []
        folderRows = [:]
        rowMeta = []
        divider = nil
        buildFavorites(space)
        buildHeader(space)
        list.children.clear()
        for item in store.listedPinnedItems(in: space, window: windowID) { addRow(item, depth: 0) }
        addDivider()
        // Settings ▸ Tabs ▸ "Show the New Tab button above tabs": else it follows Today's last tab.
        let newTabAtTop = store.settings.newTabButtonAtTop
        if newTabAtTop { addNewTabRow(space) }
        for item in store.children(of: space.todayContainerID) { addRow(item, depth: 0) }
        if !newTabAtTop { addNewTabRow(space) }
        showCreationPage(space)
        buildSpacesBar(space)
        watchJumpPillRow()
    }

    // MARK: Create a Space

    /// New Space: Arc's Create a Space page takes the space's place in the sidebar, and the
    /// window shows no tab until it is left. Asked again while it is up, its name field takes the
    /// keys. A window with no spaces of its own makes the space at once.
    /// `created` runs with the space once it is made (Move to ▸ New Space…).
    func beginSpaceCreation(created: (@MainActor (UUID) -> Void)? = nil) {
        if let page = creationPage { return page.focusName() }
        guard !store.isStandalone(window: windowID) else {
            if let made = newSpaceAtOnce() { created?(made.id) }
            return
        }
        let page = SpaceCreationPageView(store: store, window: windowID, anchor: root) { [weak self] field in
            self?.actions?.focusRenameField(field)
        } onDraft: { [weak self] in
            self?.refreshDock()
        } onEnd: { [weak self] in
            self?.endCreationPage()
        }
        page.created = created
        creationPage = page
        creationHost.child = page.root
        creationHost.visibility = .visible
        build()
    }

    /// The page was left (Create Space or Cancel): the space's part comes back.
    private func endCreationPage() {
        guard creationPage != nil else { return }
        creationPage = nil
        creationHost.child = nil
        creationHost.visibility = .collapsed
        build()
        actions?.renameEnded()
    }

    /// While the page is up the space's favorites, header and list make way for it. Another space
    /// picked (the dock, a key, the wheel) cancels it, as on the Mac.
    private func showCreationPage(_ space: Space) {
        let page = creationPage
        let shown: Visibility = page == nil ? .visible : .collapsed
        header.visibility = page == nil && !store.hidesSpaceHeader(space.id) ? .visible : .collapsed
        scroll.visibility = shown
        if page != nil { favorites.visibility = .collapsed }
        guard let page else { return }
        page.apply(palette: palette, width: favoritesWidth)
        if space.id != page.origin {
            // Not while the store is being read for this drawing.
            _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { [weak page] in page?.cancelCreation() }
        }
    }

    /// The downloads button goes in the footer, its list over the bottom of the tab list.
    func attachDownloads(button: FrameworkElement, list tray: FrameworkElement) {
        footer.children.append(button)
        root.children.append(tray)
        try? Grid.setRow(tray, 2)
    }

    /// The space's part `offset` sidebar widths from its place (+ to the right), while a switch slides.
    func slideSpace(offset: Double) {
        let x = offset * (root.actualWidth > 0 ? root.actualWidth : Self.restingWidth)
        for shift in slideShifts { shift.x = x }
    }

    var fill: Brush { palette.fill }
    var isDark: Bool { palette.isDark }
    var textColor: Brush { palette.text }
    var secondaryTextColor: Brush { palette.secondaryText }

    // MARK: Favorites

    /// Arc's grid (FavoritesLayout, #29): up to four columns that keep a tile at least as wide as
    /// it is tall, then the fewest that need no more rows; a short last row keeps the tile width.
    /// A tile's own colour (Tile Color) fills it, with a shade while it's open.
    private func buildFavorites(_ space: Space) {
        favorites.children.clear()
        favorites.columnDefinitions.clear()
        favorites.rowDefinitions.clear()
        favoriteTiles = []
        let items = store.children(of: space.favoritesContainerID).filter { $0.isTab || $0.isSplit }
        favorites.visibility = items.isEmpty ? .collapsed : .visible
        showFavoritesCard()
        let grid = FavoritesLayout(count: items.count, width: CGFloat(favoritesWidth))
        favoritesColumns = items.isEmpty ? nil : grid.columns
        guard !items.isEmpty else { return }
        let perRow = grid.columns
        for _ in 0..<perRow { favorites.columnDefinitions.append(UI.column(UI.star)) }
        for _ in 0..<grid.rows { favorites.rowDefinitions.append(UI.row(UI.pixels(Double(FavoritesLayout.tileHeight)))) }
        let open = store.selectedTabID(window: windowID).map { store.splitContaining($0)?.id ?? $0 }
        for (i, item) in items.enumerated() {
            let tileColor = item.isSplit ? nil : item.tab?.tileColor
            let dark = FavoriteTileColors.isDark(tileColor: tileColor, spaceIsDark: palette.isDark)
            let label = tileIcon(item, dark: dark, colored: tileColor != nil)
            label.horizontalAlignment = .center
            let selected = item.id == open
            // The Mac's FavoriteTileView: the pill at rest, its hover under the pointer, lighter while
            // open; a coloured tile keeps its hue with a shade over it.
            func fill(hovered: Bool) -> Brush {
                FavoriteTileColors.fill(tileColor: tileColor, selected: selected, hovered: hovered).map { UI.brush($0) }
                    ?? UI.brush(SidebarTones.favoriteTile(dark: palette.isDark, selected: selected, hovered: hovered))
            }
            let rest = fill(hovered: false), hover = fill(hovered: true)
            // Away from its pinned page, the second click of a double-click goes back there (#264).
            let away = item.tab.map { $0.url != $0.savedURL } == true
            let tile = UI.button(label, fill: rest) { [weak self] in
                guard let self else { return }
                let clicks = self.mouseClickCount(.item(item.id))
                self.dragPressed(.item(item.id))
                if FavoriteClick.action(clickCount: clicks, navigatedAway: away) == .backToPinnedPage {
                    self.actions?.resetPinnedTab(item.id)
                }
                self.select(item.id)
            }
            _ = tile.resources.insert("ButtonBackgroundPointerOver", hover)
            _ = tile.resources.insert("ButtonBackgroundPressed", hover)
            let rim: Brush = selected ? favoriteRim(item, dark: dark) : UI.clear
            tile.borderThickness = Thickness(left: 2, top: 2, right: 2, bottom: 2)
            tile.borderBrush = rim
            for key in ["ButtonBorderBrushPointerOver", "ButtonBorderBrushPressed"] { _ = tile.resources.insert(key, rim) }
            favoriteTiles.append((tile, item.id))
            tile.horizontalAlignment = .stretch
            tile.verticalAlignment = .stretch
            tile.contextFlyout = tabMenu(item)
            ArcTip.set(tile, item.displayTitle, placement: .cursor)
            favorites.children.append(tile)
            try? Grid.setRow(tile, Int32(i / perRow))
            try? Grid.setColumn(tile, Int32(i % perRow))
        }
    }

    /// The open favorite's 2 DIP rim: Arc's neutral one, or with Settings ▸ Tabs ▸ Colorful
    /// favorite outline on, its logo's colours at 72 % (FavoriteSelectionTint). The Mac sweeps
    /// them round the tile; XAML has no conic brush, so they run corner to corner.
    private func favoriteRim(_ item: SidebarItem, dark: Bool) -> Brush {
        guard store.settings.favoriteLogoOutline else { return UI.brush(SidebarTones.favoriteRim(dark: dark)) }
        let tab = item.isSplit ? store.children(of: item.id).first?.tab : item.tab
        let stops = FavoriteSelectionTint.colors(iconColors: favicons.selectionColors(forKey: tab?.iconKey), dark: dark)
        let brush = LinearGradientBrush()
        brush.startPoint = WindowsFoundation.Point(x: 0, y: 0)
        brush.endPoint = WindowsFoundation.Point(x: 1, y: 1)
        for (i, hex) in stops.enumerated() {
            let stop = GradientStop()
            stop.color = UI.brush(hex).color
            stop.offset = stops.count > 1 ? Double(i) / Double(stops.count - 1) : 0
            brush.gradientStops.append(stop)
        }
        brush.opacity = SidebarTones.favoriteLogoRimOpacity
        return brush
    }

    /// The grid's width: the sidebar's, or its fixed width before the first layout.
    var favoritesWidth: Double {
        root.actualWidth > 0 ? root.actualWidth : Self.restingWidth
    }

    /// The grid again when the sidebar's width changes its columns.
    private func favoritesWidthChanged() {
        guard let columns = favoritesColumns else { return }
        let count = favoriteTiles.count
        guard FavoritesLayout(count: count, width: CGFloat(favoritesWidth)).columns != columns else { return }
        buildFavorites(store.focusedSpace(window: windowID))
    }

    /// A tile's favicon at 20 DIPs (FavoriteTileView), or its site's first letter until the
    /// icon has loaded. A split's tile shows its first tab's. On a coloured tile the icon and
    /// letter take the tile's tone, not the space's.
    private func tileIcon(_ item: SidebarItem, dark: Bool, colored: Bool) -> FrameworkElement {
        let tab = item.isSplit ? store.children(of: item.id).first?.tab : item.tab
        if let bitmap = favicons.bitmap(forKey: tab?.iconKey, onDark: dark) {
            return UI.image(bitmap, size: 20)
        }
        let ink = colored ? (dark ? UI.brush(255, 255, 255) : UI.brush(20, 20, 24)) : palette.text
        return UI.text(Self.tileLabel(item), size: 15, color: ink, trimmed: false)
    }

    private static func tileLabel(_ item: SidebarItem) -> String {
        let name = item.tab.flatMap { URL(string: $0.url)?.host }.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
            ?? item.displayTitle
        return name.first.map { String($0).uppercased() } ?? "•"
    }

    // MARK: Header

    private func buildHeader(_ space: Space) {
        header.children.clear()
        headerTitle = nil
        // Arc's single-space mode (Settings ▸ Tabs ▸ Spaces, or the space's menu).
        header.visibility = store.hidesSpaceHeader(space.id) ? .collapsed : .visible
        if renaming.spaceID == space.id {
            let spaceID = space.id
            let field = renameField(space.title, size: 14) { [weak self] text in
                self?.store.renameSpace(spaceID, to: text)
            } isCurrent: { [weak self] in self?.renaming.spaceID == spaceID } end: { [weak self] in self?.renaming.spaceID = nil }
            field.margin = Thickness(left: 2, top: 0, right: 2, bottom: 0)
            header.children.append(field)
            return
        }
        let name = UI.text("\(space.emoji) \(space.title)".trimmingCharacters(in: .whitespaces), size: 14, color: palette.text)
        // Arc: clicking the space's name folds its pinned tabs away.
        let spaceID = space.id
        let title = UI.button(name, padding: Thickness(left: 6, top: 4, right: 6, bottom: 4)) { [weak self] in
            guard let self else { return }
            if self.mouseClickCount(.space(spaceID)) == 2, Self.clickModifiers == 0 {
                self.beginRename(space: spaceID)
                return
            }
            self.store.togglePinnedCollapsed(self.store.focusedSpaceID(window: self.windowID))
        }
        title.horizontalAlignment = .stretch
        title.horizontalContentAlignment = .left
        title.contextFlyout = spaceMenu(space)
        headerTitle = title
        header.children.append(title)
    }

    // MARK: Renaming

    /// Rename… on a tab or folder row (renameTab): its name turns into a field.
    func beginRename(item id: UUID) {
        renaming.spaceID = nil
        renaming.itemID = id
    }

    /// Rename Space…: the header's name turns into a field, on the space shown.
    func beginRename(space id: UUID) {
        if store.focusedSpaceID(window: windowID) != id { store.focusSpace(id, window: windowID) }
        // A header Arc's single-space mode hides has no name to edit.
        guard !store.hidesSpaceHeader(id) else { return }
        renaming.itemID = nil
        renaming.spaceID = id
    }

    /// A field over a name: Return keeps what was typed, Escape the old name, and leaving the
    /// field keeps it too, as the Mac's field ends editing. `isCurrent` says whether this field
    /// is still the rename (a redraw drops it and fires its LostFocus); `end` clears it.
    private func renameField(_ text: String, size: Double = 13, commit: @escaping @MainActor (String) -> Void,
                             isCurrent: @escaping @MainActor () -> Bool, end: @escaping @MainActor () -> Void) -> TextBox {
        let field = TextBox()
        field.text = text
        field.fontSize = size
        field.minHeight = 0
        field.padding = Thickness(left: 6, top: 3, right: 6, bottom: 3)
        field.isSpellCheckEnabled = false
        field.isTextPredictionEnabled = false
        field.verticalAlignment = .center
        field.horizontalAlignment = .stretch
        try? AutomationProperties.setName(field, "Name")
        kept.append(field)
        let finish: @MainActor (Bool) -> Void = { [weak self, weak field] keep in
            guard isCurrent() else { return }
            let typed = field?.text ?? text
            end()
            if keep { commit(typed) }
            self?.actions?.renameEnded()
        }
        field.previewKeyDown.addHandler { _, args in
            guard let args else { return }
            switch Int32(truncatingIfNeeded: args.key.rawValue) {
            case 0x0D: args.handled = true; finish(true)   // Return
            case 0x1B: args.handled = true; finish(false)  // Escape
            default: break
            }
        }
        field.lostFocus.addHandler { _, _ in finish(true) }
        field.loaded.addHandler { [weak self, weak field] _, _ in
            guard let self, let field, isCurrent() else { return }
            self.actions?.focusRenameField(field)
        }
        return field
    }

    // MARK: Rows

    private func addRow(_ item: SidebarItem, depth: Int) {
        let before = list.children.count
        defer { if !item.isFolder { noteRow(item, depth: depth, at: before) } }
        if item.isFolder {
            addFolderRow(item, depth: depth)
        } else if item.isSplit {
            let titles = store.splitRowTitle(item.id)
            let selected = store.selectedTabID(window: windowID).map { store.splitContaining($0)?.id == item.id } ?? false
            // A click opens the split on the pane last focused in it (Arc: focusItemID).
            let panes = store.paneTabIDs(for: item.children.first ?? item.id)
            let focus = item.split?.focusTabID.flatMap { panes.contains($0) ? $0 : nil } ?? panes.first
            appendRow(icon: .text("⧉"), title: titles, depth: depth, selected: selected, unread: false, closable: nil,
                      menu: splitMenu(item, open: selected), renames: item.id) { [weak self] in
                self?.dragPressed(.item(item.id))
                if let focus { self?.select(focus) }
            }
        } else if item.isTab {
            let closable = item.id
            let selected = store.isSelected(item.id, window: windowID)
            // A site in Developer Mode: its host and port under the title, a ring round the open tab.
            let developer = item.tab.map { store.settings.isDeveloperMode(url: $0.url) } ?? false
            // Arc: the favicon of a pinned tab away from its pinned page takes it back there (#139).
            let away = store.isPinned(item.id) && item.tab.map { $0.url != $0.savedURL } == true
            appendRow(icon: .favicon(item.tab?.iconKey), title: item.displayTitle, subtitle: item.tab?.sidebarSubtitle(developerMode: developer),
                      depth: depth, selected: selected, ring: developer && selected, unread: item.isUnread, closable: closable,
                      sound: TabSound.button(muted: item.tab?.muted ?? false, audible: audibleTabIDs.contains(item.id), editing: renaming.itemID == item.id).map { (item.id, $0) },
                      peek: peekBadge?.tabID == item.id ? .favicon(peekBadge?.iconKey) : nil, menu: tabMenu(item), renames: item.id,
                      homeIcon: away ? item.id : nil) { [weak self] in
                self?.dragPressed(.item(item.id))
                self?.clickTab(item.id, awayFromHome: away)
            }
        }
    }

    /// A folder's row (the Mac's FolderRowView and SidebarMenus.folder): its glyph open or closed,
    /// with its symbol (Change Icon…) and colour (Icon Color ▸). A closed folder still lists the
    /// open tab, and any tab peeked out of it, under itself (FolderPeek, #85).
    private func addFolderRow(_ folder: SidebarItem, depth: Int) {
        let open = store.isExpanded(folder.id)
        let id = folder.id
        let menu = MenuFlyout()
        menu.items.append(UI.menuItem(open ? "Collapse" : "Expand") { [weak self] in self?.store.setExpanded(id, !open) })
        if !folder.isLiveFolder {
            menu.items.append(UI.menuItem("Change Icon…") { [weak self] in self?.showFolderIconPicker(id) })
            menu.items.append(UI.menuItem("Rename…") { [weak self] in self?.beginRename(item: id) })
            menu.items.append(UI.menuItem("New Folder Inside") { [weak self] in
                guard let self else { return }
                // Arc names a new folder at once, first inside the folder, which opens.
                let inner = self.store.createFolder(named: "New Folder", in: id, index: 0)
                self.store.setExpanded(id, true)
                self.beginRename(item: inner.id)
            })
            menu.items.append(folderIconColorMenu(folder))
        }
        // Arc's Move to ▸ (upstream #662): the folder goes to the end of that space's Pinned with
        // all it holds.
        if let move = moveToMenu(id) { menu.items.append(move) }
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Delete Folder (archives tabs)") { [weak self] in self?.store.deleteFolder(id) })
        let peeked = open ? [] : store.peekedTabs(in: id)
        let row = appendRow(icon: .folder(open: open, symbol: folder.folderSymbol, style: folder.folderIcon, peeking: !peeked.isEmpty),
                  title: folder.displayTitle, depth: depth, selected: false, unread: false, closable: nil,
                  menu: menu, renames: folder.isLiveFolder ? nil : id) { [weak self] in
            // A drag that starts here leaves the folder as it was.
            self?.dragPressed(.item(id)) { [weak self] in self?.store.setExpanded(id, open) }
            self?.store.setExpanded(id, FolderPeek.clickOpens(expanded: open))
        }
        noteRow(folder, depth: depth, at: list.children.count - 1)
        folderRows[id] = row
        if !open {
            row.pointerEntered.addHandler { [weak self] _, _ in self?.folderPreview.entered(id) }
            row.pointerExited.addHandler { [weak self] _, _ in self?.folderPreview.exited(id) }
            row.pointerPressed.addHandler { [weak self] _, _ in self?.folderPreview.pressed() }
        }
        guard open else {
            for tab in peeked { addRow(tab, depth: depth + 1) }
            return
        }
        let children = store.children(of: id)
        if children.isEmpty {
            let empty = UI.text("Empty", size: 12, color: palette.secondaryText)
            empty.margin = Thickness(left: Double(depth + 1) * 16 + 10, top: 2, right: 0, bottom: 4)
            list.children.append(empty)
        }
        for child in children { addRow(child, depth: depth + 1) }
    }

    /// Icon Color ▸ Auto, White, Black (the Mac's SidebarMenus.iconColor).
    private func folderIconColorMenu(_ folder: SidebarItem) -> MenuFlyoutSubItem {
        let sub = MenuFlyoutSubItem()
        sub.text = "Icon Color"
        for (title, style) in [("Auto", FolderIconStyle?.none), ("White", .white), ("Black", .black)] {
            let entry = ToggleMenuFlyoutItem()
            entry.text = title
            entry.isChecked = folder.folderIcon == style
            entry.click.addHandler { [weak self] _, _ in self?.store.setFolderIcon(style, for: folder.id) }
            sub.items.append(entry)
        }
        return sub
    }

    /// Change Icon…: Arc's picker under the folder's row (the Mac's FolderIconPicker): "Icon",
    /// Remove Icon while it has one, and the 24 symbols eight to a row, its own one filled.
    func showFolderIconPicker(_ id: UUID) {
        guard let folder = store.item(id), let row = folderRows[id] else { return }
        let current = folder.folderSymbol
        let flyout = Flyout()
        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 8
        let header = StackPanel()
        header.orientation = .horizontal
        header.spacing = 14
        let title = UI.text("Icon", size: 13, trimmed: false)
        title.fontWeight = UWP.FontWeight(weight: 700)
        title.verticalAlignment = .center
        header.children.append(title)
        if current != nil {
            let bin = FontIcon()
            bin.glyph = "\u{E74D}"  // Delete
            bin.fontSize = 14
            let remove = UI.button(bin, padding: Thickness(left: 4, top: 2, right: 4, bottom: 2)) { [weak self, weak flyout] in
                self?.store.setFolderSymbol(nil, for: id)
                try? flyout?.hide()
            }
            try? AutomationProperties.setName(remove, "Remove Icon")
            ArcTip.set(remove, "Remove Icon")
            header.children.append(remove)
        }
        panel.children.append(header)
        let grid = Grid()
        for _ in 0..<8 { grid.columnDefinitions.append(UI.column(UI.pixels(31))) }
        for _ in 0..<3 { grid.rowDefinitions.append(UI.row(UI.pixels(31))) }
        for (i, symbol) in FolderSymbol.allCases.enumerated() {
            let mark = Self.folderSymbolText(symbol, size: 14)
            let cell = UI.button(mark, fill: symbol == current ? palette.selected : nil,
                                 padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self, weak flyout] in
                self?.store.setFolderSymbol(symbol, for: id)
                try? flyout?.hide()
            }
            cell.width = 29
            cell.height = 29
            try? AutomationProperties.setName(cell, symbol.title)
            ArcTip.set(cell, symbol.title)
            grid.children.append(cell)
            try? Grid.setRow(cell, Int32(i / 8))
            try? Grid.setColumn(cell, Int32(i % 8))
        }
        panel.children.append(grid)
        flyout.content = panel
        kept.append(flyout)
        try? flyout.showAt(row)
    }

    /// A folder symbol in one colour: Segoe UI Symbol's character for it (Arc draws its own).
    static func folderSymbolText(_ symbol: FolderSymbol, size: Double, color: Brush? = nil) -> TextBlock {
        let t = UI.text(folderSymbolCharacter(symbol), size: size, color: color, trimmed: false)
        t.fontFamily = FontFamily("Segoe UI Symbol")
        t.isColorFontEnabled = false
        t.horizontalAlignment = .center
        t.verticalAlignment = .center
        return t
    }

    private static func folderSymbolCharacter(_ symbol: FolderSymbol) -> String {
        switch symbol {
        case .star: return "\u{2605}"
        case .bookmark: return "\u{1F516}"
        case .heart: return "\u{2665}"
        case .bolt: return "\u{26A1}"
        case .triangle: return "\u{25B2}"
        case .asterisk: return "\u{2731}"
        case .bell: return "\u{1F514}"
        case .lightbulb: return "\u{1F4A1}"
        case .chat: return "\u{1F4AC}"
        case .people: return "\u{1F465}"
        case .tools: return "\u{1F527}"
        case .egg: return "\u{2B2E}"
        case .circle: return "\u{25CF}"
        case .moon: return "\u{263E}"
        case .planet: return "\u{2644}"
        case .leaf: return "\u{1F343}"
        case .cloud: return "\u{2601}"
        case .paw: return "\u{1F43E}"
        case .cutlery: return "\u{1F374}"
        case .airplane: return "\u{2708}"
        case .music: return "\u{266A}"
        case .video: return "\u{1F3AC}"
        case .code: return "</>"
        case .skull: return "\u{1F480}"
        }
    }

    /// What leads a row: a tab's favicon (a globe until it loads), or a mark for folders and splits.
    private enum RowIcon {
        case favicon(String?)
        case text(String)
        /// A folder's glyph: open or closed, its symbol and fixed colour, and three dots while it
        /// lists tabs from inside it closed.
        case folder(open: Bool, symbol: FolderSymbol?, style: FolderIconStyle?, peeking: Bool)
    }

    private func rowIcon(_ icon: RowIcon) -> FrameworkElement {
        switch icon {
        case .text(let mark):
            return UI.text(mark, color: palette.secondaryText, trimmed: false)
        case .folder(let open, let symbol, let style, let peeking):
            let ink: Brush = switch style {
            case .white?: UI.brush(255, 255, 255)
            case .black?: UI.brush(0, 0, 0)
            case nil: palette.secondaryText
            }
            let cell = Grid()
            cell.width = 16
            cell.height = 16
            let glyph = FontIcon()
            glyph.glyph = open ? "\u{E838}" : "\u{E8B7}"  // FolderOpen, Folder
            glyph.fontSize = 15
            glyph.foreground = ink
            cell.children.append(glyph)
            if let symbol {
                let mark = Self.folderSymbolText(symbol, size: 7, color: ink)
                mark.margin = Thickness(left: 0, top: 3, right: 0, bottom: 0)
                cell.children.append(mark)
            } else if peeking {
                let dots = UI.text("•••", size: 5, color: ink, trimmed: false)
                dots.horizontalAlignment = .center
                dots.verticalAlignment = .center
                dots.margin = Thickness(left: 0, top: 3, right: 0, bottom: 0)
                cell.children.append(dots)
            }
            return cell
        case .favicon(let key):
            if let bitmap = favicons.bitmap(forKey: key, onDark: palette.isDark) { return UI.image(bitmap, size: 16) }
            // FaviconView's fallback: a globe in the tertiary text colour.
            let globe = FontIcon()
            globe.glyph = WinGlyph.code("globe")
            globe.fontSize = 13
            globe.width = 16
            globe.foreground = palette.secondaryText
            return globe
        }
    }

    @discardableResult
    private func appendRow(icon: RowIcon, title: String, subtitle: String? = nil, depth: Int, selected: Bool, ring: Bool = false,
                           unread: Bool, closable: UUID?, sound: (UUID, TabSound)? = nil, peek: RowIcon? = nil, menu: MenuFlyout?, renames: UUID? = nil,
                           homeIcon: UUID? = nil, _ action: @escaping @MainActor () -> Void) -> Grid {
        let row = Grid()
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        row.margin = Thickness(left: Double(depth) * 16, top: 0, right: 0, bottom: 0)

        let label = StackPanel()
        label.orientation = .horizontal
        label.spacing = 8
        let lead = rowIcon(icon)
        lead.verticalAlignment = .center
        label.children.append(lead)
        // The press starts on the icon (it reaches the icon before the row's button takes it).
        if let id = homeIcon {
            lead.pointerPressed.addHandler { [weak self] _, _ in self?.iconPress = (id, GetTickCount64()) }
            // Arc's slash after the icon of a pinned tab away from its page (SidebarSlashView):
            // 4 DIPs after the icon, the name 5 DIPs on.
            // The projection has no Shapes.Line: a slash in the name's font stands in for the stroke.
            let slash = UI.text("/", size: 14, color: palette.secondaryText, trimmed: false)
            slash.fontWeight = UWP.FontWeight(weight: 600)
            slash.isHitTestVisible = false
            slash.verticalAlignment = .center
            slash.margin = Thickness(left: -4, top: 0, right: -3, bottom: 0)
            label.children.append(slash)
        }
        if let id = renames, renaming.itemID == id {
            // Rename…: the row's name is a field until Return, Escape or a click elsewhere.
            let own = store.item(id)?.title
            let field = renameField(own ?? title) { [weak self] text in
                self?.store.rename(id, to: text)
            } isCurrent: { [weak self] in self?.renaming.itemID == id } end: { [weak self] in self?.renaming.itemID = nil }
            let editing = Grid()
            editing.columnDefinitions.append(UI.column(UI.auto))
            editing.columnDefinitions.append(UI.column(UI.star))
            editing.columnSpacing = 6
            label.children.clear()
            editing.children.append(lead)
            editing.children.append(field)
            try? Grid.setColumn(field, 1)
            // The row's pill stays behind the field (a Border rounds its fill; a Grid doesn't).
            let pill = Border()
            pill.padding = Thickness(left: 8, top: 2, right: 4, bottom: 2)
            pill.cornerRadius = CornerRadius(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
            if selected { pill.background = palette.selected }
            pill.child = editing
            row.children.append(pill)
            try? Grid.setColumnSpan(pill, 2)
            list.children.append(row)
            return row
        }
        // Arc 1.171's speaker between the favicon and the title; a click mutes or unmutes the tab.
        if let sound {
            let (id, speaker) = sound
            let glyph = FontIcon()
            glyph.glyph = WinGlyph.code(speaker.symbol)
            glyph.fontSize = 12
            glyph.foreground = palette.secondaryText
            let button = UI.button(glyph, padding: Thickness(left: 2, top: 0, right: 2, bottom: 0)) { [weak self] in
                self?.actions?.toggleMute(id)
            }
            button.verticalAlignment = .center
            try? AutomationProperties.setName(button, speaker.help)
            ArcTip.set(button, speaker.help)
            label.children.append(button)
        }
        let name = UI.text(title.isEmpty ? "New Tab" : title, color: palette.text)
        if unread { name.fontWeight = UWP.FontWeight(weight: 600) }
        if let subtitle {
            let lines = StackPanel()
            lines.orientation = .vertical
            lines.verticalAlignment = .center
            lines.children.append(name)
            lines.children.append(UI.text(subtitle, size: 11, color: palette.secondaryText))
            label.children.append(lines)
        } else {
            label.children.append(name)
        }

        // The Peek's badge sits at the end of the row's own pill (Arc's modalIcon).
        var content: FrameworkElement = label
        if let peek {
            let inside = Grid()
            inside.columnDefinitions.append(UI.column(UI.star))
            inside.columnDefinitions.append(UI.column(UI.auto))
            inside.children.append(label)
            let badge = rowIcon(peek)
            badge.verticalAlignment = .center
            badge.margin = Thickness(left: 6, top: 0, right: 0, bottom: 0)
            try? AutomationProperties.setName(badge, "Peek")
            inside.children.append(badge)
            try? Grid.setColumn(badge, 1)
            content = inside
        }
        let pick = UI.button(content, fill: selected ? palette.selected : nil) { [weak self] in
            guard let self else { return }
            let clicks: Int
            if let id = renames {
                clicks = self.mouseClickCount(.item(id))
                if clicks == 2, Self.clickModifiers == 0, !self.wentHomeJustNow(id) {
                    self.beginRename(item: id)
                    return
                }
            } else {
                self.clickTracker.cancel()
                clicks = 1
            }
            self.rowClickCount = clicks
            action()
            self.rowClickCount = 1
        }
        pick.horizontalAlignment = .stretch
        pick.horizontalContentAlignment = peek == nil ? .left : .stretch
        if let menu { pick.contextFlyout = menu }
        row.children.append(pick)
        try? Grid.setColumn(pick, 0)

        // Arc's trailing end (TabRowTrailing, #243): at rest the name runs to 21 DIPs from the
        // pill's end and an unread tab shows a dot where the close button goes; on hover the
        // close button shows inside the pill, 6 DIPs from its end, and the name stops 15 before it.
        if let id = closable {
            let rest = Double(TabRowTrailing.tail(controls: []))
            let hover = Double(TabRowTrailing.tail(controls: [TabRowTrailing.Control(width: CGFloat(Self.closeSize))]))
            let padding = pick.padding
            let pad: @MainActor (Button?, Double) -> Void = { button, tail in
                button?.padding = Thickness(left: padding.left, top: padding.top, right: tail, bottom: padding.bottom)
            }
            pad(pick, rest)
            let tab = store.item(id)?.tab
            let pinned = store.isPinned(id)
            let kind = SidebarClose.tab(pinned: pinned, current: selected, navigatedAway: pinned && tab.map { $0.url != $0.savedURL } == true,
                                        peeked: false)
            let glyph = FontIcon()
            glyph.glyph = WinGlyph.code(kind.minus ? "minus" : "xmark")
            glyph.fontSize = 11
            glyph.foreground = palette.secondaryText
            let close = UI.button(glyph, padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) { [weak self] in
                guard let self else { return }
                if kind.action == .archive, pinned {
                    self.store.archiveTab(id, reason: .manual)
                } else {
                    self.actions?.closeTab(id)
                }
            }
            close.width = Self.closeSize
            close.height = Self.closeSize
            close.horizontalAlignment = .right
            close.verticalAlignment = .center
            close.margin = Thickness(left: 0, top: 0, right: Double(TabRowTrailing.endInset), bottom: 0)
            close.visibility = .collapsed
            let help = kind.help.replacingOccurrences(of: "⌘W", with: "Ctrl+W")
            try? AutomationProperties.setName(close, help)
            ArcTip.set(close, help)
            row.children.append(close)
            try? Grid.setColumn(close, 0)
            var dot: WinUI.Ellipse?
            if unread, !selected {
                let d = WinUI.Ellipse()  // not GDI's Ellipse
                d.width = Self.unreadDotSize
                d.height = Self.unreadDotSize
                d.fill = palette.secondaryText
                d.isHitTestVisible = false
                d.horizontalAlignment = .right
                d.verticalAlignment = .center
                d.margin = Thickness(left: 0, top: 0, right: Double(TabRowTrailing.endInset) + (Self.closeSize - Self.unreadDotSize) / 2, bottom: 0)
                row.children.append(d)
                try? Grid.setColumn(d, 0)
                kept.append(d)
                dot = d
            }
            // Weak in the row's own handlers (a strong capture would keep the row alive through
            // its children); `kept` holds them until the next build.
            kept += [close, glyph, pick]
            row.pointerEntered.addHandler { [weak close, weak pick, weak dot] _, _ in
                close?.visibility = .visible
                dot?.visibility = .collapsed
                pad(pick, hover)
            }
            row.pointerExited.addHandler { [weak close, weak pick, weak dot] _, _ in
                close?.visibility = .collapsed
                dot?.visibility = .visible
                pad(pick, rest)
            }
        }
        if ring { addDeveloperRing(to: row) }
        list.children.append(row)
        return row
    }

    /// Arc's ring round a Developer Mode site's open tab (CraCore's DeveloperTabRing): yellow
    /// under black dashes at 80 %, the dashes cut to the row's size.
    private func addDeveloperRing(to row: Grid) {
        let yellow = WinUI.Rectangle(), dashes = WinUI.Rectangle()  // not GDI's Rectangle
        yellow.stroke = UI.brush(255, 204, 0)
        dashes.stroke = UI.brush(0, 0, 0, alpha: UInt8((DeveloperTabRing.dashAlpha * 255).rounded()))
        kept += [yellow, dashes]
        for ring in [yellow, dashes] {
            ring.strokeThickness = DeveloperTabRing.lineWidth
            ring.isHitTestVisible = false
            row.children.append(ring)
            try? Grid.setColumnSpan(ring, 2)
        }
        dashes.sizeChanged.addHandler { [weak yellow, weak dashes] _, _ in
            guard let yellow, let dashes else { return }
            // The stroke sits inside the shape, so its middle runs 1 DIP in, as the Mac's path does.
            let w = dashes.actualWidth - DeveloperTabRing.lineWidth, h = dashes.actualHeight - DeveloperTabRing.lineWidth
            let r = DeveloperTabRing.cornerRadius(width: w, height: h)
            for ring in [yellow, dashes] {
                ring.radiusX = r
                ring.radiusY = r
            }
            // XAML counts dashes in stroke widths.
            let d = DeveloperTabRing.dash(width: w, height: h) / DeveloperTabRing.lineWidth
            let pattern = DoubleCollection()
            pattern.append(d)
            pattern.append(d)
            dashes.strokeDashArray = pattern
        }
    }

    /// The line between the pinned tabs and Today.
    private func addDivider() {
        let line = Border()
        line.height = 1
        line.background = palette.tile
        line.margin = Thickness(left: 4, top: 6, right: 4, bottom: 6)
        list.children.append(line)
        divider = line
    }

    private func addNewTabRow(_ space: Space) {
        let row = Grid()
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        let add = UI.button(UI.text("+  New Tab", color: palette.secondaryText)) { [weak self] in self?.actions?.beginNewTab() }
        add.horizontalAlignment = .stretch
        add.horizontalContentAlignment = .left
        row.children.append(add)
        try? Grid.setColumn(add, 0)
        if !store.children(of: space.todayContainerID).isEmpty {
            // Arc's "Clear": every Today tab goes to the archive.
            let clear = UI.button("Clear", color: palette.secondaryText) { [weak self] in self.map { $0.store.clearToday(playing: $0.audibleTabIDs) } }
            row.children.append(clear)
            try? Grid.setColumn(clear, 1)
        }
        list.children.append(row)
    }

    private func select(_ id: UUID) {
        store.selectTab(id, window: windowID)
    }

    private static var clickModifiers: Int {
        (GetKeyState(0x11) < 0 ? 1 : 0) | (GetKeyState(0x10) < 0 ? 2 : 0) | (GetKeyState(0x12) < 0 ? 4 : 0)
    }

    /// WinUI's double-tap recognizer belongs to the old Button, which the first click may
    /// replace. Count physical presses against the item instead; keyboard/Invoke has no pair.
    private func mouseClickCount(_ target: SidebarClick.Target) -> Int {
        let primary: Int32 = GetSystemMetrics(23) != 0 ? 0x02 : 0x01  // SM_SWAPBUTTON
        var point = POINT()
        guard GetAsyncKeyState(primary) < 0, GetCursorPos(&point) else {
            clickTracker.cancel()
            return 1
        }
        return clickTracker.press(target, at: Double(GetTickCount64()) / 1000, x: Double(point.x), y: Double(point.y),
                                  modifiers: Self.clickModifiers, interval: Double(GetDoubleClickTime()) / 1000,
                                  distanceX: Double(GetSystemMetrics(36)) / 2, distanceY: Double(GetSystemMetrics(37)) / 2)
    }

    /// A click on a tab row (on its release): on the favicon of a pinned tab away from its page
    /// it goes back there, with Ctrl the page moves out to a new Today tab first (the Mac's ⌘);
    /// anywhere else it selects the tab (PinnedIconClick, SidebarRowViews' click).
    private func clickTab(_ id: UUID, awayFromHome: Bool) {
        let now = GetTickCount64()
        let onIcon = iconPress.map { $0.id == id && now &- $0.at < 2000 } ?? false
        iconPress = nil
        let last = lastTabClick.flatMap { $0.id == id && now &- $0.at <= UInt64(GetDoubleClickTime()) ? $0 : nil }
        let action = PinnedIconClick.action(clickCount: rowClickCount, onIcon: onIcon, navigatedAway: awayFromHome,
                                            command: GetKeyState(0x11) < 0, previousWentBack: last?.wentBack ?? false)
        lastTabClick = (id, now, action.wentBack || (action == .nothing))
        switch action {
        case .separateFromPinnedTab:
            actions?.separatePinnedTab(id)
        case .backToPinnedPage:
            actions?.resetPinnedTab(id)
            select(id)
        case .nothing:
            break
        case .row:
            select(id)
        }
    }

    /// This row's last click went back home from its icon, within a double-click.
    private func wentHomeJustNow(_ id: UUID) -> Bool {
        guard let last = lastTabClick, last.id == id, last.wentBack else { return false }
        return GetTickCount64() &- last.at <= 2 * UInt64(GetDoubleClickTime())
    }

    // MARK: Menus

    private func tabMenu(_ item: SidebarItem) -> MenuFlyout {
        let id = item.id
        let menu = MenuFlyout()
        let favorite = store.isFavorite(id), pinned = store.isPinned(id)
        if favorite {
            menu.items.append(UI.menuItem("Remove from Favorites", action: "favoriteTab") { [weak self] in self?.store.removeFromFavorites(id) })
        } else {
            menu.items.append(UI.menuItem("Add to Favorites", action: "favoriteTab") { [weak self] in self?.store.addToFavorites(id) })
            menu.items.append(UI.menuItem(pinned ? "Unpin" : "Pin", action: "pinTab") { [weak self] in self?.store.togglePinned(id) })
        }
        if item.isTab {
            // Favorites draw as tiles, which have no name to edit.
            if !favorite { menu.items.append(UI.menuItem("Rename…", action: "renameTab") { [weak self] in self?.beginRename(item: id) }) }
            if favorite { menu.items.append(tileColorMenu(item)) }
            // Arc: "Add Split View" on the open tab, "Open in Split View" on another in its space.
            if store.isSelected(id, window: windowID) {
                menu.items.append(UI.menuItem("Add Split View", action: "addSplitView") { [weak self] in self?.actions?.addSplitView() })
            } else if store.selectedTabID(window: windowID) != nil, store.spaceID(ofItem: id) == store.focusedSpaceID(window: windowID) {
                menu.items.append(UI.menuItem("Open in Split View") { [weak self] in self?.actions?.openInSplitView(id) })
            }
            menu.items.append(UI.menuItem("Duplicate", action: "duplicateTab") { [weak self] in _ = self?.store.duplicateTab(id) })
            // Always offered: the Mac dims it on a quiet tab, but Windows can't hear players in
            // other sites' frames or Web Audio (AudibleProbe), so a quiet-looking tab may play.
            menu.items.append(UI.menuItem(TabSound.menuTitle(muted: item.tab?.muted ?? false), action: "muteTab") { [weak self] in
                self?.actions?.toggleMute(id)
            })
            // A pinned tab away from its pinned page (the Mac's tab menu).
            if pinned, let tab = item.tab, tab.url != tab.savedURL {
                menu.items.append(MenuFlyoutSeparator())
                menu.items.append(UI.menuItem("Back to Pinned Page") { [weak self] in self?.actions?.resetPinnedTab(id) })
            }
            // Arc's Edit Pinned Page ▸ (SidebarMenus.pinnedURLItems): not on a live folder's rows.
            if pinned, let tab = item.tab, tab.liveItemURL == nil {
                let edit = MenuFlyoutSubItem()
                edit.text = "Edit Pinned Page"
                let replace = UI.menuItem("Replace Pinned URL with Current") { [weak self] in self?.store.setPinnedHomeToCurrent(id) }
                replace.isEnabled = tab.url != tab.savedURL
                edit.items.append(replace)
                edit.items.append(UI.menuItem("Edit…") { [weak self] in self?.actions?.editPinnedURL(id) })
                menu.items.append(edit)
            }
        }
        // An incognito window's tabs stay in it.
        let others = store.isIncognito(item: id) ? [] : store.orderedSpaces.filter { $0.id != store.spaceID(ofItem: id) }
        if !others.isEmpty {
            let move = MenuFlyoutSubItem()
            move.text = "Move to Space"
            for space in others {
                move.items.append(UI.menuItem("\(space.emoji) \(space.title)") { [weak self] in self?.store.moveTab(id, toSpace: space.id) })
            }
            menu.items.append(move)
        }
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem(pinned ? "Close (Unload)" : "Close Tab", action: "closeTab") { [weak self] in self?.actions?.closeTab(id) })
        // Arc's Today tab menu: Archive Tabs Below, when there are tabs below it.
        if let parent = item.parentID, let rows = store.item(parent)?.children, rows.last != id,
           store.spaceID(ofItem: id).flatMap(store.space)?.todayContainerID == parent {
            menu.items.append(UI.menuItem("Archive Tabs Below") { [weak self] in self?.store.archiveTabsBelow(id) })
        }
        return menu
    }

    /// A favorite's Tile Color ▸ (the Mac's favorite menu): Default, the presets and its own
    /// colour ticked (FavoriteTileColors), then Use This Color for All Favorites in its space.
    private func tileColorMenu(_ item: SidebarItem) -> MenuFlyoutSubItem {
        let id = item.id, current = item.tab?.tileColor
        let sub = MenuFlyoutSubItem()
        sub.text = "Tile Color"
        for choice in FavoriteTileColors.choices(current: current) {
            let entry = ToggleMenuFlyoutItem()
            entry.text = choice.title
            entry.isChecked = choice.checked
            if let hex = choice.hex {
                let dot = FontIcon()
                dot.glyph = "\u{E91F}"  // Segoe Fluent Icons' filled circle
                dot.foreground = UI.brush(hex)
                entry.icon = dot
            }
            entry.click.addHandler { [weak self] _, _ in self?.store.setTileColor(choice.hex, for: [id]) }
            sub.items.append(entry)
        }
        sub.items.append(MenuFlyoutSeparator())
        sub.items.append(UI.menuItem("Use This Color for All Favorites") { [weak self] in
            guard let self, let space = self.store.spaceID(ofItem: id).flatMap(self.store.space) else { return }
            self.store.setTileColor(current, for: self.store.favoriteTabs(in: space).map(\.id))
        })
        return sub
    }

    /// Arc's Move to ▸ (upstream #662) for a folder or a split: every space, its own ticked, then
    /// New Space…, which moves it once the space is made. None from a private window.
    private func moveToMenu(_ id: UUID) -> MenuFlyoutSubItem? {
        guard !store.isIncognito(item: id) else { return nil }
        let move = MenuFlyoutSubItem()
        move.text = "Move to"
        let own = store.spaceID(ofItem: id)
        for space in store.orderedSpaces where !store.isIncognito(space: space.id) {
            let entry = ToggleMenuFlyoutItem()
            entry.text = "\(space.emoji) \(space.title)"
            entry.isChecked = space.id == own
            entry.click.addHandler { [weak self] _, _ in
                guard let self, space.id != own else { return }
                self.store.moveTab(id, toSpace: space.id, window: self.windowID)
            }
            move.items.append(entry)
        }
        move.items.append(MenuFlyoutSeparator())
        move.items.append(UI.menuItem("New Space…") { [weak self] in
            self?.beginSpaceCreation { [weak self] made in
                guard let self else { return }
                self.store.moveTab(id, toSpace: made, window: self.windowID)
            }
        })
        return move
    }

    /// Arc 1.171's split menu where the Windows app has the feature (SidebarMenus.split on the Mac).
    private func splitMenu(_ split: SidebarItem, open: Bool) -> MenuFlyout {
        let id = split.id
        let menu = MenuFlyout()
        let panes = store.children(of: id).filter(\.isTab)
        menu.items.append(UI.menuItem("Separate All Tabs") { [weak self] in self?.store.separateAll(id) })
        // Arc greys it out while the split is closed (no pane to add next to).
        let add = UI.menuItem("Add Tab…") { [weak self] in self?.actions?.addPane(toSplit: id) }
        add.isEnabled = open && panes.count < SplitPaneLayout.Constants.maximumPanes
        menu.items.append(add)
        let vertical = split.split?.orientation == .vertical
        menu.items.append(UI.menuItem(vertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View", action: "flipSplitOrientation") { [weak self] in
            self?.store.flipSplitOrientation(id)
        })
        menu.items.append(MenuFlyoutSeparator())
        for pane in panes {
            let options = MenuFlyoutSubItem()
            options.text = pane.displayTitle
            let paneID = pane.id
            options.items.append(UI.menuItem("Separate from Split View") { [weak self] in self?.store.separateFromSplit(paneID) })
            options.items.append(UI.menuItem("Close") { [weak self] in self?.actions?.closeSplitPane(paneID) })
            menu.items.append(options)
        }
        menu.items.append(MenuFlyoutSeparator())
        // Arc's way back to the panes from a renamed split or one with an icon.
        if store.splitHasOwnNameOrIcon(id) {
            menu.items.append(UI.menuItem("Reset Name and Icon") { [weak self] in self?.store.resetSplitNameAndIcon(id) })
        }
        menu.items.append(UI.menuItem("Rename…") { [weak self] in self?.beginRename(item: id) })
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Duplicate") { [weak self] in
            guard let self else { return }
            _ = self.store.duplicateSplit(id, window: self.windowID)
        })
        if let move = moveToMenu(id) { menu.items.append(move) }
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Archive Item") { [weak self] in
            guard let self else { return }
            for pane in panes { self.store.archiveTab(pane.id, reason: .manual) }
        })
        return menu
    }

    func spaceMenu(_ space: Space) -> MenuFlyout {
        let menu = MenuFlyout()
        if !store.isIncognito(space: space.id) {
            menu.items.append(UI.menuItem("Rename Space…") { [weak self] in self?.beginRename(space: space.id) })
            menu.items.append(UI.menuItem("Change Space Icon…") { [weak self] in self?.showIconPicker(space: space.id) })
            menu.items.append(UI.menuItem("Edit Theme Color…") { [weak self] in self?.showStyleEditor(space: space.id) })
        }
        menu.items.append(UI.menuItem("New Folder", action: "newFolder") { [weak self] in self?.newFolder(in: space, atTop: false) })
        if !store.isIncognito(space: space.id) {
            menu.items.append(UI.menuItem("New Space") { [weak self] in self?.newSpace() })
        }
        menu.items.append(UI.menuItem("Clear Today", action: "clearToday") { [weak self] in self.map { $0.store.clearToday(space.id, playing: $0.audibleTabIDs) } })
        if !store.isIncognito(space: space.id) { menu.items.append(profileMenu(space)) }
        menu.items.append(searchEngineMenu(space))
        if !store.isIncognito(space: space.id) {
            // Arc's group of Manage Spaces… and, with one space, Hide Space Header (SpaceMenuLayout).
            menu.items.append(MenuFlyoutSeparator())
            menu.items.append(UI.menuItem("Manage Spaces…", action: "manageSpaces") { [weak self] in self?.actions?.showLibrary(.spaces) })
        }
        if store.spaceOrder.count == 1 && !store.isIncognito(space: space.id) {
            menu.items.append(UI.menuItem("Hide Space Header") { [weak self] in self?.store.settings.showSpaceHeaderOnSingleSpace = false })
        }
        if store.spaceOrder.count > 1 {
            menu.items.append(MenuFlyoutSeparator())
            menu.items.append(UI.menuItem("Delete Space…", action: "deleteSpace") { [weak self] in self?.actions?.confirmDeleteSpace(space.id) })
        }
        return menu
    }

    /// GitHub #306, not in Arc: the engine the command bar searches in this space (SpaceSearchEngineMenu,
    /// the Mac's SpaceMenu.addSearchEngines). Windows reads no Chromium engine list, so Cra's own stands in.
    private func searchEngineMenu(_ space: Space) -> MenuFlyoutSubItem {
        let sub = MenuFlyoutSubItem()
        sub.text = "Search Engine"
        let rows = SpaceSearchEngineMenu(defaultEngine: ChromiumSearchEngine(store.settings.searchEngine), engines: [],
                                         spaceKeyword: space.searchEngine)
        func choice(_ row: SpaceSearchEngineMenu.Row) -> ToggleMenuFlyoutItem {
            let item = ToggleMenuFlyoutItem()
            item.text = row.title
            item.isChecked = row.isOn
            let id = space.id
            item.click.addHandler { [weak self] _, _ in self?.store.setSearchEngine(row.keyword, forSpace: id) }
            return item
        }
        sub.items.append(choice(rows.defaultRow))
        sub.items.append(MenuFlyoutSeparator())
        for row in rows.choices { sub.items.append(choice(row)) }
        return sub
    }

    /// Arc's Set Profile: Default, the profiles (the space's ticked), New Profile….
    private func profileMenu(_ space: Space) -> MenuFlyoutSubItem {
        let sub = MenuFlyoutSubItem()
        sub.text = "Set Profile"
        func choice(_ title: String, _ id: UUID?) -> ToggleMenuFlyoutItem {
            let item = ToggleMenuFlyoutItem()
            item.text = title
            item.isChecked = space.profileID == id
            item.click.addHandler { [weak self] _, _ in self?.store.setProfile(id, forSpace: space.id) }
            return item
        }
        sub.items.append(choice(store.profileName(nil), nil))
        for p in store.profiles { sub.items.append(choice(p.name, p.id)) }
        sub.items.append(MenuFlyoutSeparator())
        sub.items.append(UI.menuItem("New Profile…") { [weak self] in self?.actions?.newProfile(forSpace: space.id) })
        return sub
    }

    // MARK: Spaces

    /// Change Space Icon…: Arc's picker at the space's name in the header, or at its dock icon
    /// when the header is hidden or shows another space.
    func showIconPicker(space id: UUID) {
        guard let space = store.space(id) else { return }
        let anchor = id == store.focusedSpaceID(window: windowID) && header.visibility == .visible ? headerTitle : nil
        guard let target = anchor ?? spaceCells.first(where: { $0.id == id })?.element ?? headerTitle else { return }
        let picker = SpaceIconPickerView(current: space.icon, dark: space.theme.isDark) { [weak self] icon in
            guard let self, var s = self.store.space(id) else { return }
            s.icon = icon
            self.store.updateSpace(s)
        }
        iconPicker = picker
        picker.show(at: target)
    }

    /// Edit Theme Color… (and Edit Space…): Arc's theme editor against the sidebar's edge. The
    /// sidebar redraws under it as the theme changes, so it hangs off the sidebar itself.
    func showStyleEditor(space id: UUID) {
        guard let space = store.space(id) else { return }
        try? styleEditor?.flyout.hide()
        let editor = SpaceStyleEditorView(store: store, space: space)
        styleEditor = editor
        editor.show(beside: root)
    }

    /// New Folder in the pinned section of `space` (the one in front by default), named at once
    /// as in Arc: at the top for the command (the Mac's), after the rest from the space's menu.
    func newFolder(in space: Space? = nil, atTop: Bool = true) {
        let space = space ?? store.focusedSpace(window: windowID)
        beginRename(item: store.createFolder(named: "New Folder", in: space.pinnedContainerID, index: atTop ? 0 : nil).id)
    }

    func newSpace() { beginSpaceCreation() }

    /// A space made at once, named after its place (the Library's +, and a window with no spaces of
    /// its own, where the page has nowhere to go).
    @discardableResult
    func newSpaceAtOnce() -> Space? {
        let n = store.spaceOrder.count
        // Arc's New Space starts on the profile of the space it was opened from.
        let profile = SpaceProfiles.forNewSpace(from: store.focusedSpace(window: windowID), profiles: store.profiles)
        let space = store.createSpace(title: "Space \(n + 1)", emoji: Self.spaceEmoji[n % Self.spaceEmoji.count])
        if profile != nil { store.setProfile(profile, forSpace: space.id) }
        return store.space(space.id)
    }
}
