import CraCEFWin
import CraCore
import Foundation
import Observation
import UWP
import WinAppSDK
import WindowsFoundation
import WinSDK
import WinUI

/// One browser window on the shared SidebarStore: the toolbar, address box and sidebar on
/// the left, the open tab's page on the right (or its split's panes, side by side or stacked).
/// The Windows counterpart of MainWindowController and BrowserManager, smaller for now: a
/// page made when its tab is first shown and closed when the tab leaves the sidebar or is
/// unloaded. Each window draws one of the store's window sessions (WindowSession): its focused
/// space and selected tabs; a private window's session has an incognito space of its own and
/// its pages load in the off-the-record profile.
@MainActor
final class BrowserWindow {
    let store: SidebarStore
    /// The store's window session this window shows.
    let windowID: UUID
    /// A private (incognito) window.
    let isIncognito: Bool
    /// The app's windows: new ones, and this one going.
    private weak var host: BrowserWindowHost?
    /// XAML in the sidebar column only, so the page gets real clicks (HostWindow).
    private(set) var window: HostWindow!
    private var sidebar: SidebarView!
    private let sidebarPanel = Grid()
    /// What the sidebar's gradient was last painted for (paintSidebarGradient).
    private var gradientKey: [Double] = []
    private var gradientColors: [RGB] = []
    /// The space the sidebar last drew and its colours, for the slide to the next (slideIfSwitched).
    private var slidSpace: UUID?
    private var lastDrawnColors: [RGB]?
    /// A space switch's slide under way: the colours it fades from, its side (+1 right, -1 left),
    /// when it began and how far the colours have come.
    private var slide: (from: [RGB], direction: Double, started: Double, blend: Double)?
    private var slideTimer: WinAppSDK.DispatcherQueueTimer?
    /// The toolbar, the address pill and the sidebar: what the Library takes the place of.
    private var sidebarParts: [FrameworkElement] = []
    /// Arc's Library in the sidebar (LibraryView): the page shown, nil while it shows the tabs.
    /// Arc keeps it per window and opens it again on the page last shown.
    private var library: LibraryView!
    private var libraryPage: LibraryPage?
    /// The hidden sidebar brought out over the page (Ctrl+S hides it); set up with the window.
    private var floatingSidebar: FloatingSidebar!
    /// What the column shows as last laid out: docked beside the pages, or hidden.
    private var sidebarDocked = true
    private var lastLibraryPage: LibraryPage = .downloads
    /// The open tab's address; a click opens the command bar on it (Arc's URL bar in the sidebar).
    private let address = TextBlock()
    private var addressButton: Button!
    /// The sidebar's toggle button, which takes the keyboard when the toolbar has the address.
    private var sidebarToggle: Button!
    /// Arc's downloads list over the bottom of the sidebar, and its button in the footer.
    private var downloads: DownloadsTray!
    /// Downloads this window's pages started (the stall check), and the ones it has recorded.
    private var windowDownloads: Set<UInt32> = []
    /// Delete Space…'s question while it is up.
    private var deleteSpaceSheet: AppDialog?
    private var finishedDownloads: Set<UInt32> = []
    private var downloadWatchdog: WinAppSDK.DispatcherQueueTimer?
    private let dispatcher: WinAppSDK.DispatcherQueue
    /// The window's HWND: every page is a child window of it.
    private var hwnd: UInt = 0
    /// The window's HWND, for the hover tips' tones (ArcTip).
    var nativeHandle: UInt { hwnd }
    /// Arc paints a browser window's tips from its space's palette.
    var tooltipTones: TooltipTones { TooltipTones(theme: store.focusedSpace(window: windowID).theme) }

    /// Pages by tab id.
    private var pages: [UUID: WebPage] = [:]
    /// Every page this window made that Chromium hasn't finished closing: the window waits for
    /// them before it goes (CEF's DoClose order). Other windows' pages don't count.
    private var livePages: Set<ObjectIdentifier> = []
    /// The selected tab's page: the focused pane, which takes the keyboard and the commands.
    private weak var shownPage: WebPage?
    /// When each page this window made was created, until its first focus: Chromium focuses a
    /// new browser by itself once it has a window, after the redraw that showed it (a split's
    /// new pane after Add To Split), and that focus mustn't select its tab.
    private var newPages: [ObjectIdentifier: Date] = [:]
    private var shownTabID: UUID?
    /// Tabs whose video went into Picture in Picture as they were left: it comes back with them.
    private var autoPictureInPicture: Set<UUID> = []
    /// The panes on screen, in order: the selected tab, or every pane of its split. Their frames
    /// and the gaps between them, in physical pixels relative to the client area.
    private var paneIDs: [UUID] = []
    private var paneFrames: [UUID: PixelRect] = [:]
    /// A split's panes' own bars (Arc 1.171, GitHub #178), by pane position, and where each sits:
    /// over its pane's top, which the page leaves free (paneFrames are the pages').
    private var paneBars: [ToolbarView] = []
    private var paneBarFrames: [UUID: PixelRect] = [:]
    private var hoveredPaneBar: Int?
    /// The Split View Options menu, kept while it shows (a MenuFlyout made from Swift is only a wrapper).
    private var splitOptionsMenu: MenuFlyout?
    private var paneGaps: [PixelRect] = []
    /// The same layout in DIPs from the page area's top left, for hit-testing the dividers.
    private var paneLayoutResult = SplitPaneLayout.Result()
    private var paneOrientation: SplitOrientation = .horizontal
    /// A sidebar tab dragged over the panes: the split it would make, the window over the region
    /// that shows it, and the tab shown in place of the dragged one (splitDragMoved).
    private var splitDropTarget: SplitDropProposal.Target?
    private var splitDropOverlay: UInt = 0
    private var splitDropSwap: (dragged: UUID, shown: UUID)?
    /// A divider being dragged: the one after pane `divider`, where it was pressed, and the
    /// factors then. `factors` follows the pointer and is saved to the split on release.
    private var paneDrag: (divider: Int, x: Int32, y: Int32, start: [UUID: CGFloat], factors: [UUID: CGFloat])?
    /// Ctrl+T, Ctrl+L: ranked by CraCore's SuggestionEngine, drawn in a window of its own over the page.
    private var engine: SuggestionEngine!
    private var commandBar: CommandBarView!
    private var commandWindow: FloatingWindow?
    private var commandBarHeight = CommandBarView.height(forRows: 0)
    /// The bar closed because another window came to the front: that window keeps the keyboard.
    private var commandBarDeactivated = false
    /// Ctrl+F: find in the shown page, in a window of its own at the page's top right.
    private let findBar = FindBarView()
    /// Right-click Back or Forward: the tab's pages that way (BackForwardMenu, #416). Kept here:
    /// a MenuFlyout made from Swift is only a wrapper, freed with its last Swift reference.
    private let backMenu = MenuFlyout()
    private let forwardMenu = MenuFlyout()
    /// Right-click ↻ (the toolbar's or the sidebar's): ReloadMenuItems, as the Mac's ReloadMenu.
    private let reloadMenu = MenuFlyout()
    /// The shown page's history rows, as last read, and which page they are from.
    private var historyRows: [BackForwardMenu.Direction: [BackForwardMenu.Row]] = [:]
    private var historyPage: ObjectIdentifier?
    /// Arc's Developer Mode bar over a site's page (HostWindow's strip).
    private let developerBar = DeveloperBarView()
    private var developerTabID: UUID?
    /// Arc's toolbar over the page (View ▸ Show Toolbar), in the same strip.
    private let pageToolbar = ToolbarView()
    /// What the strip shows now.
    private var topBar: WindowTopBar = .none
    /// Automatically Hide Toolbar: the toolbar floats over the page's top (ToolbarAutoHide.floats),
    /// out while the tracker says so, from a 30 ms pointer poll (Windows sends no hover over pages).
    private var toolbarFloats = false
    private var toolbarTracker = ToolbarAutoHideTracker()
    private var toolbarPoll: WinAppSDK.DispatcherQueueTimer?
    /// The sidebar's ← → ↻ and its address pill, which the toolbar takes over while it shows.
    private var sidebarNavigation: [FrameworkElement] = []
    private var findWindow: FloatingWindow?
    private var findVisible = false
    private var refreshQueued = false
    /// The window is waiting for Chromium to close its pages; then it closes for good.
    private var closing = false
    private var readyToClose = false
    private var closeTimer: WinAppSDK.DispatcherQueueTimer?
    /// Arc's loading bar at the window's top middle, for the page in front.
    private var loadingBar: LoadingBar?
    /// The docked sidebar's edge, which a drag resizes (`SidebarResize`).
    private var sidebarEdge: SidebarEdge?
    private var sidebarResize: SidebarResize?
    /// The drag under way hid the sidebar; dragged back, it shows again.
    private var hiddenByResize = false
    /// The tab sidebar's width in DIPs: the one saved (`WindowPrefs.sidebarWidth`, shared by
    /// every window), or the drag's while one is on.
    private var tabSidebarWidth = WindowPrefs().sidebarWidth { didSet { syncHeaderLayout(); syncPillPins(reload: false) } }
    /// The sidebar header's row (Arc's regular or narrow layout, SidebarHeaderLayout) and its parts.
    private var headerRow: StackPanel?
    private var headerButtons: (back: Button, forward: Button, reload: Button, more: Button)?
    /// The narrow header's ••• menu (Reload, Toggle Sidebar), kept: a Swift MenuFlyout is a wrapper.
    private let headerMoreMenu = MenuFlyout()
    /// Tries the sidebar's keyboard focus again while the XAML is still loading (focusSidebar).
    private var sidebarFocusRetry: WinAppSDK.DispatcherQueueTimer?
    /// Ctrl+,: one for the app, made the first time any window opens it, then hidden and shown
    /// again (over the window that asked).
    private static var settingsWindow: SettingsWindow?
    /// Help ▸ Essential Keyboard Shortcuts, made the first time it is asked for.
    private var essentialShortcutsCard: EssentialShortcutsCard?
    /// Use Both's check that the page kept a press (watchUseBoth).
    private var useBothWatch: ScheduledWork?
    /// Permission requests for the user: one card at a time, and only for a page on screen; a
    /// tab behind waits until it's shown, as Chrome does (CraCore's `PermissionLine`, #286).
    private var permissions = PermissionLine<PagePermission>()
    private let permissionPrompt = PermissionPromptView()
    private var permissionWindow: FloatingWindow?
    private var permissionHeight = 120.0
    private let profileDialog = ProfileDialogView()
    /// "Quit Cra?" over this window while it asks (Arc's dialog sheet).
    private var quitSheet: AppDialog?
    /// Edit Pinned Page ▸ Edit… on a pinned tab or favorite.
    private lazy var editPinnedDialog = EditPinnedURLDialog()
    private var profileWindow: FloatingWindow?
    private var profileDialogHeight = 400.0
    private let importDialog = ImportDialogView()
    private var importWindow: FloatingWindow?
    private var importDialogHeight = 300.0
    private var onboarding: OnboardingView?
    private var onboardingWindow: FloatingWindow?
    /// The sliders button at the end of the address pill, and the Site Control Center it opens.
    private var sliders: Button!
    private let slidersGlyph = FontIcon()
    /// The pill's pinned extensions, before the sliders (syncPillPins), and what they show.
    private let pillPins = StackPanel()
    private var pillPinsShown: [ToolbarView.Pin]?
    /// The profile's pins as last read, for a sidebar resize to fit again without reading them.
    private var pillPinsAll: [ToolbarView.Pin] = []
    /// The pill's pin buttons by extension id, kept for their popups to hang from.
    private var pillPinButtons: [String: Button] = [:]
    private let siteControl = SiteControlCenterView()
    private var siteControlWindow: FloatingWindow?
    /// When the Site Control Center last closed because another window took the front: a press
    /// on the sliders right then is the click that closed it, and doesn't open it again.
    private var siteControlClosed = Date.distantPast
    /// An extension's popup page (ExtensionLaunch.popupWindow), under the sliders.
    private var extensionPopup: ExtensionPopup?
    private var toast: ToastView!
    /// Tab sleeping: when each page went out of sight, when a page that refused may be asked
    /// again, and the minute's pass (BrowserManager.sleepIdleTabs on the Mac).
    private var hiddenAt: [UUID: Date] = [:]
    private var sleepAskAfter: [UUID: Date] = [:]
    private var sleepTimer: WinAppSDK.DispatcherQueueTimer?
    /// Which pages make sound (AudibleProbe), asked every second: stock CEF doesn't say.
    private var audibleTimer: WinAppSDK.DispatcherQueueTimer?
    private var audible = AudibleProbe.Tracker()
    /// Arc's now-playing player at the bottom of the sidebar (#33): its cards and their view.
    private var nowPlaying = NowPlayingList()
    private let nowPlayingTray = NowPlayingTray()
    /// Arc's Ctrl+Tab switcher over the space's recent tabs.
    private var tabSwitcher: TabSwitcherWindow!
    /// Each tab's wait for its first response, and the tab whose "Still waiting" toast is up
    /// (SlowResponseNotice, the Mac's MainWindowController).
    private var slowResponses = SlowResponseNotices()
    private var slowResponseToastTab: UUID?
    private var slowResponseCheck: ScheduledWork?
    private lazy var clock = WinScheduler(queue: dispatcher)
    /// A full-page capture is running.
    private var capturing = false
    /// The Peek closed last over this window and the tab it came from: Arc's Ctrl+Shift+T brings
    /// it back when nothing was archived after it.
    var closedPeek: (url: String, tabID: UUID?, at: Date)?

    /// What a new window opens when the sidebar has nothing to show.
    static let startPage = "https://crabrowser.app"

    /// `frame`: where the window opens (a restored or cascaded one); nil lets Windows place it.
    /// `newWindow`: opened by New Window, so it starts with the command bar rather than a page.
    init(store: SidebarStore, session: WindowSession, frame: WindowFrame?, newWindow: Bool = false,
         dispatcher: WinAppSDK.DispatcherQueue, host: BrowserWindowHost) throws {
        self.store = store
        windowID = session.id
        isIncognito = session.isIncognito
        self.host = host
        self.dispatcher = dispatcher
        let incognito = session.isIncognito
        engine = SuggestionEngine(store: store,
                                  commands: { WinKeyBindings.shared.barCommands(display: \.windowsDisplay, inPrivateWindow: incognito) },
                                  load: WinSuggestLoader.load)
        commandBar = CommandBarView(engine: engine, store: store, windowID: session.id)
        sidebar = SidebarView(store: store, windowID: session.id, actions: self)
        downloads = DownloadsTray(history: .shared, dispatcher: dispatcher)
        sidebar.attachNowPlaying(nowPlayingTray.root)
        sidebar.attachDownloads(button: downloads.button, list: downloads.list)
        // A private window shows only its own space: no Spaces page (Manage Spaces…).
        let spacesPage = incognito ? nil : SpacesManagerView(store: store, windowID: session.id, actions: self)
        library = LibraryView(store: store, history: .shared, dispatcher: dispatcher, spaces: spacesPage, actions: self)
        downloads.onClick = { [weak self] in self?.toggleLibrary() }
        let pointer: () -> (x: Double, y: Double)? = { [weak self] in
            guard let self, let window = self.window, let host = HWND(bitPattern: self.hwnd) else { return nil }
            var p = POINT(x: Int32.min, y: Int32.min)
            _ = GetCursorPos(&p)
            guard p.x != Int32.min else { return nil }
            _ = ScreenToClient(host, &p)
            // The XAML island starts at the client area's top left, or where it floats.
            let origin = window.columnOrigin
            return (Double(p.x - origin.x) / window.scale, Double(p.y - origin.y) / window.scale)
        }
        downloads.pointer = pointer
        sidebar.pointer = pointer
        sidebar.folderPreview.host = { [weak self] in self?.window }
        // A sidebar drag holds the mouse in the window itself, so no page sees it go by.
        sidebar.captureMouse = { [weak self] in
            guard let self, let host = HWND(bitPattern: self.hwnd) else { return }
            _ = SetCapture(host)
        }
        tabSidebarWidth = SidebarResizeHandle.restored(store.prefs.sidebarWidth)
        let strip = Grid()
        strip.children.append(developerBar.root)
        strip.children.append(pageToolbar.root)
        window = try HostWindow(content: makeLayout(), topBar: strip, sidebarWidth: tabSidebarWidth, frame: frame)
        window.title = Self.title(nil, incognito: isIncognito)
        hwnd = window.hwnd
        loadingBar = LoadingBar(owner: hwnd, dispatcher: dispatcher)
        sidebarEdge = SidebarEdge(owner: hwnd)
        window.onLayout = { [weak self] _ in
            self?.paintSidebarGradient()
            self?.placeLoadingBar()
            self?.placeSidebarEdge()
            self?.syncLibraryWidth()
            self?.repositionPeeks()
            self?.layoutPanes()
            self?.placeCommandBar()
            self?.placeFindBar()
            self?.placePermissionPrompt()
            self?.hideSiteControlCenter()
        }
        window.onMove = { [weak self] in
            self?.placeLoadingBar()
            self?.placeSidebarEdge()
            self?.repositionPeeks()
            self?.placeFindBar()
            self?.placePermissionPrompt()
            self?.hideSiteControlCenter()
            self?.toast?.ownerMoved()
        }
        window.onMouse = { [weak self] event in self?.handlePaneMouse(event) }
        window.cursor = { [weak self] x, y in self?.paneCursor(x: x, y: y) }
        window.onActivate = { [weak self] in
            guard let self, !self.closing else { return }
            self.store.activeWindowID = self.windowID
        }
        window.onActiveLookChanged = { [weak self] active in
            guard let self, !self.closing else { return }
            self.sidebar.windowActive = active
            self.queueRefresh()
        }
        window.onMoveEnded = { [weak self] in
            self?.saveFrame()
            // Dragging the title bar made the window under a Peek the active one: the card takes
            // the keyboard back once the move or resize is over.
            _ = self?.handKeyboardToPeek()
        }
        window.onFocus = { [weak self] in
            guard let self, !self.closing, !self.commandBar.isOpen else { return }
            // A redraw the store asked for first, so the keyboard goes to the page now selected
            // (a Peek's Add To Split selects the new pane just before the card goes and the window
            // takes the keyboard back).
            if self.refreshQueued { self.refresh() }
            if self.handKeyboardToPeek() { return }
            self.focusContent()
        }
        makeFloatingSidebar()
        wireSidebarEdge()
        makeCommandBar()
        makeFindBar()
        makeDeveloperBar()
        makeToolbar()
        makePermissionPrompt()
        makeProfileDialog()
        makeImportDialog()
        makeSiteControlCenter()
        toast = ToastView(owner: window) { [weak self] in self?.pageOnScreen() }
        startTabSleeping()
        startAudibleProbe()
        makeTabSwitcher()
        // Chromium closes its pages before their parent window goes (CEF's DoClose order).
        window.shouldClose = { [weak self] in
            guard let self, !self.readyToClose else { return true }
            // Closing the last window quits Cra: "Quit Cra?" or "Downloads in progress" first.
            guard self.closing || self.host?.confirmQuit(closing: self) != false else { return false }
            self.saveFrame()
            guard !self.canFinishClosing else { return true }
            self.beginClosing()
            return false
        }
        window.onClose = { [weak self] in
            guard let self else { return }
            self.host?.windowDidClose(self)
        }
        store.activeWindowID = windowID
        if newWindow {
            refresh()
            openCommandBar(.newTab)
            return
        }
        if store.selectedTab(window: windowID) == nil && store.visibleTabs(in: store.focusedSpaceID(window: windowID)).isEmpty {
            store.createTab(url: Self.startPage, window: windowID)
        }
        refresh()
        // A space with no tab selected shows no page, and show() hands the keyboard on only when
        // the page changes. The window took the front before onFocus was set (HostWindow shows
        // itself), so the sidebar takes the keys here; else Ctrl+T did nothing until a click.
        if shownPage == nil { focusContent() }
    }

    /// "Cra", or the tab's title before it; a private window says so, as Chrome's do.
    private static func title(_ tab: String?, incognito: Bool) -> String {
        let app = incognito ? "Cra (Incognito)" : "Cra"
        guard let tab, !tab.isEmpty else { return app }
        return "\(tab) - \(app)"
    }

    /// Brings the window to the front (another Cra launch, a link from another app, a Little
    /// Window's page moved in). A redraw the store asked for comes first: taking the front hands
    /// the keyboard to the page on screen, and a stale one taking it would select its tab again
    /// over the one just picked (pageDidReceiveFocus; seen when a Little Window's page moved in).
    func activate() {
        if refreshQueued { refresh() }
        window.activate()
    }

    /// Asks the window to close as its close button does (Ctrl+Shift+W).
    func requestClose() {
        guard !closing, window.shouldClose?() ?? true else { return }
        // After the key's event, as the close button's is: the XAML that delivered the key goes
        // with the window, and tearing it down inside its own handler traps.
        _ = try? dispatcher.tryEnqueue { [weak self] in self?.window?.close() }
    }

    /// Where the window is, for the next launch (windows.json). A minimized or maximized window
    /// keeps the frame it had before.
    func saveFrame() {
        guard !closing, let hwnd = HWND(bitPattern: hwnd), !IsIconic(hwnd), !IsZoomed(hwnd) else { return }
        let frame = window.frame.string
        guard store.window(windowID).id == windowID, store.window(windowID).frame != frame else { return }
        store.updateWindow(windowID) { $0.frame = frame }
    }

    /// The window's frame on screen, for a new window cascaded from it.
    var frame: WindowFrame { window.frame }
    var workArea: WindowFrame? { window.workArea }
    var scale: Double { window.scale }

    /// The tab has a live page in this window.
    func hasPage(_ id: UUID) -> Bool { pages[id] != nil }

    /// A Little Window's live page as tab `id`'s (its "Open in <Space>"): moved into this window,
    /// history, scroll position and sign-ins included (BrowserManager.adopt on the Mac). A page in
    /// another profile than the tab's space loads there again (syncPages).
    func adopt(_ page: WebPage, for id: UUID) {
        guard !closing else { return page.close() }
        pages[id]?.close()
        page.delegate = self
        page.userInfo = id
        page.isVisible = false
        page.move(toParent: hwnd, frame: paneFrames[id] ?? contentFrame())
        livePages.insert(ObjectIdentifier(page))
        pages[id] = page
        queueRefresh()
    }

    // MARK: Store → window

    /// Draws the sidebar and shows the open tab's page, then waits for the next change to
    /// anything they read (the store is Observable).
    private func refresh() {
        refreshQueued = false
        guard !closing else { return }
        withObservationTracking {
            sidebar.build()
            slideIfSwitched(to: store.focusedSpaceID(window: windowID))
            lastDrawnColors = sidebar.palette.colors
            paintSidebarGradient()
            applyPaneColors(store.focusedSpace(window: windowID).theme)
            downloads.apply(sidebar.palette, fill: sidebar.fill)
            if libraryPage != nil {
                library.build(sidebar.palette, dark: sidebar.isDark)
                syncLibraryWidth()
            }
            syncSidebarMode()
            syncSidebarWidth()
            syncSidebarSide()
            placeSidebarEdge()
            syncPages()
            syncNowPlaying()
            syncSlowResponse()
            syncTopBar()
            showAddress(store.selectedTab(window: windowID)?.tab?.url ?? "")
        } onChange: { [weak self] in
            // Called inside the change, on the main thread: draw once it is done.
            onMain { self?.queueRefresh() }
        }
    }

    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        _ = try? dispatcher.tryEnqueue { [weak self] in self?.refresh() }
    }

    private func syncPages() {
        // A page can't change its Chromium profile: one whose tab moved to a space on another
        // profile, or whose space changed profile, closes and loads its address again there
        // (BrowserManager.pruneMissingTabs on the Mac).
        for (id, page) in pages where store.item(id)?.isTab != true || !inRightProfile(page, tab: id) {
            page.close()
            pages[id] = nil
        }
        // Split view: the selected tab's split decides which panes are on screen. An empty pane
        // (Arc's "Search or Enter URL…") has no page yet.
        let selected = store.selectedTab(window: windowID)
        let panes = selected.map { store.paneTabIDs(for: $0.id) } ?? []
        var shown: [UUID: WebPage] = [:]
        for id in panes {
            guard let tab = store.item(id)?.tab, !tab.url.isEmpty else { continue }
            shown[id] = pages[id] ?? makePage(for: id, url: tab.url)
        }
        paneIDs = panes
        layoutPanes()
        for (id, page) in pages where shown[id] == nil { page.isVisible = false }
        for page in shown.values { page.isVisible = true }
        noteHidden(shown: Set(shown.keys))
        if !permissions.isEmpty { askNextPermission() }
        show(selected.flatMap { shown[$0.id] }, tab: selected?.id)
        window.title = Self.title(selected?.displayTitle, incognito: isIncognito)
    }

    private func inRightProfile(_ page: WebPage, tab id: UUID) -> Bool {
        page.isIncognito || page.profilePath == store.profilePath(item: id)
    }

    private func makePage(for id: UUID, url: String) -> WebPage {
        let frame = paneFrames[id] ?? contentFrame()
        let profile = store.profilePath(item: id)
        let page: WebPage
        // The profile's spare, made ahead, when there is one ready (SparePagesWin); then the next.
        if SparePage.canTake(engine: .chromium, isEasel: false, incognito: isIncognito),
           let spare = SparePagesWin.shared.take(profilePath: profile) {
            spare.adopt(delegate: self, parent: hwnd, frame: frame, url: url)
            page = spare
        } else {
            page = WebPage(parent: hwnd, frame: frame, url: url, incognito: isIncognito, profilePath: profile, delegate: self)
        }
        if !isIncognito { SparePagesWin.shared.refill(profilePath: profile, parent: hwnd, frame: contentFrame(), clock: clock) }
        livePages.insert(ObjectIdentifier(page))
        newPages[ObjectIdentifier(page)] = Date()
        page.userInfo = id
        page.isVisible = false
        if store.item(id)?.tab?.muted == true { page.setAudioMuted(true) }
        pages[id] = page
        // The tab's back and forward list from before (#273): Back and Forward step through it
        // while the page has nothing of its own that way.
        if !isIncognito, let saved = PageListStore.shared.load(id), saved.restores(at: url) {
            pageLists[ObjectIdentifier(page)] = saved
        }
        return page
    }

    // MARK: Back and forward across a relaunch

    /// The list each page started with (PageList, #273), as Back and Forward have stepped it, and
    /// how many entries the page's own list had at its last save.
    private var pageLists: [ObjectIdentifier: PageList] = [:]
    private var pageEntryCounts: [ObjectIdentifier: Int] = [:]

    /// Saves the tab's list once its page has loaded: Chromium's own list on top of the one the
    /// page started with.
    private func savePageList(_ page: WebPage) {
        guard !page.isIncognito, let id = tabID(of: page), pages[id] === page else { return }
        page.sendDevToolsMethod("Page.getNavigationHistory") { [weak self, weak page] json, _ in
            guard let self, let page, let json, let live = PageList.live(history: json) else { return }
            let key = ObjectIdentifier(page)
            self.pageEntryCounts[key] = live.entries.count
            let base = self.pageLists[key] ?? PageList(entries: [], index: 0, savedAt: Date())
            PageListStore.shared.save(base.merged(live: live.entries, liveIndex: live.index, savedAt: Date()), for: id)
            if page === self.shownPage { self.syncToolbar() } else { self.syncPaneBars() }
        }
    }

    /// Back from the saved list: the page is replaced by the one before it. False when there is
    /// none (the page has its own page behind, or the list starts here).
    private func savedBack(_ page: WebPage) -> Bool {
        let key = ObjectIdentifier(page)
        guard let step = pageLists[key]?.back(pageCanGoBack: page.canGoBack) else { return false }
        pageLists[key] = step.list
        page.executeJavaScript(PageList.replaceScript(step.url))
        return true
    }

    private func savedForward(_ page: WebPage) -> Bool {
        let key = ObjectIdentifier(page)
        guard let step = pageLists[key]?.forward(pageCanGoForward: page.canGoForward, pageEntries: pageEntryCounts[key] ?? 1)
        else { return false }
        pageLists[key] = step.list
        page.executeJavaScript(PageList.replaceScript(step.url))
        return true
    }

    private func canGoBackInSaved(_ page: WebPage) -> Bool {
        pageLists[ObjectIdentifier(page)]?.back(pageCanGoBack: page.canGoBack) != nil
    }

    private func canGoForwardInSaved(_ page: WebPage) -> Bool {
        let key = ObjectIdentifier(page)
        return pageLists[key]?.forward(pageCanGoForward: page.canGoForward, pageEntries: pageEntryCounts[key] ?? 1) != nil
    }

    private func goForward() {
        guard let page = shownPage else { return }
        if !savedForward(page) { page.goForward() }
    }

    /// Focuses the selected tab's page (the panes are already on screen, syncPages).
    private func show(_ page: WebPage?, tab id: UUID?) {
        let changed = id != shownTabID
        if shownPage !== page {
            shownPage = page
            if libraryPage != nil {
                // The Library keeps the keyboard: a space changed under it (Alt+1–9).
                focusContent()
            } else if let page {
                page.setFocused(true)
            } else {
                // Nothing to show (an empty space): keys would stay with the hidden page.
                focusSidebar()
            }
        }
        let left = shownTabID
        shownTabID = id
        // Another tab in front: its bar as it is, without the widening or the flash.
        syncLoadingBar(animated: false)
        guard changed else { return }
        pictureInPictureOnTabChange(from: left, to: id)
        showAddress(page.map { _ in store.item(id ?? UUID())?.tab?.url ?? "" } ?? "")
        // An empty tab (a new pane) waits for an address.
        if id != nil && page == nil { openCommandBar(.editURL) }
    }

    /// Arc's "Enable Picture in Picture when you leave a video tab" (Settings ▸ Advanced; the Site
    /// Control Center can turn it off for a site): a video playing aloud in the tab left goes out
    /// into Picture in Picture, and back into its page when the tab is shown again
    /// (BrowserManager.leaveTab and returnToTab on the Mac). A tab still in a split pane isn't left.
    private func pictureInPictureOnTabChange(from left: UUID?, to shown: UUID?) {
        if let shown, autoPictureInPicture.remove(shown) != nil { pages[shown]?.exitPictureInPicture() }
        guard let left, left != shown, !paneIDs.contains(left), let page = pages[left],
              store.settings.allowsAutoPictureInPicture(url: page.currentURL) else { return }
        page.requestPictureInPicture(automatic: true) { [weak self] answer in
            guard let self, answer == .entered else { return }
            // Back on the tab before the page answered: its video comes straight back.
            if self.shownTabID == left { page.exitPictureInPicture() } else { self.autoPictureInPicture.insert(left) }
        }
    }

    /// Closes every page, then the window once Chromium is done with them (or after 3 s).
    private func beginClosing() {
        guard !closing else { return }
        closing = true
        SparePagesWin.shared.drop(parent: hwnd)
        commandBar.close()
        hideFindBar()
        hideSiteControlCenter()
        loadingBar?.close()
        loadingBar = nil
        sidebarEdge?.close()
        sidebarEdge = nil
        extensionPopup?.close()
        toast.hide()
        permissionWindow?.hide()
        for request in permissions.all { request.answer(false) }
        permissions = PermissionLine()
        let open = Array(pages.values)
        pages.removeAll()
        shownPage = nil
        paneIDs = []
        paneDrag = nil
        for page in open { page.close() }
        // A Peek's card is owned by this window: its page closes before the window goes.
        host?.closePeeks(over: self)
        // Popup hosts and pages already on their way out count too (livePages).
        closeTimer = try? dispatcher.createTimer()
        closeTimer?.interval = TimeSpan(duration: 3 * 10_000_000)
        closeTimer?.isRepeating = false
        closeTimer?.tick.addHandler { [weak self] _, _ in self?.finishClosing() }
        try? closeTimer?.start()
        if canFinishClosing { finishClosing() }
    }

    /// No page of this window's and no Peek over it waits for Chromium.
    private var canFinishClosing: Bool { livePages.isEmpty && host?.hasPeek(over: self) != true }

    /// A Peek over this window closed: the window may be waiting for it to go.
    func peekDidClose() {
        if host?.hasPeek(over: self) != true {
            sidebar.peekBadge = nil
            queueRefresh()
        }
        if closing, canFinishClosing { _ = try? dispatcher.tryEnqueue { [weak self] in self?.finishClosing() } }
    }

    private func finishClosing() {
        guard !readyToClose else { return }
        readyToClose = true
        stopToolbarPoll()
        try? closeTimer?.stop()
        closeTimer = nil
        window.close()
    }

    private func tabID(of page: WebPage) -> UUID? { page.userInfo as? UUID }

    // MARK: Layout

    private func makeLayout() -> UIElement {
        sidebarPanel.padding = Thickness(left: 10, top: 10, right: 10, bottom: 10)
        for height in [UI.auto, UI.auto, UI.star] { sidebarPanel.rowDefinitions.append(UI.row(height)) }

        let toolbar = StackPanel()
        toolbar.orientation = .horizontal
        toolbar.spacing = 2
        // Arc's sidebar button: hides the sidebar, or docks a hidden one that is out (Ctrl+S).
        let sidebarGlyph = FontIcon()
        sidebarGlyph.glyph = WinGlyph.code("sidebar.left")
        sidebarGlyph.fontSize = 13
        let sidebarButton = UI.button(sidebarGlyph) { [weak self] in self?.toggleSidebar() }
        sidebarToggle = sidebarButton
        ArcTip.set(sidebarButton, "Toggle Sidebar")
        try? AutomationProperties.setName(sidebarButton, "Toggle Sidebar")
        toolbar.children.append(sidebarButton)
        let back = UI.button("\u{2190}") { [weak self] in self?.goBack() }
        let forward = UI.button("\u{2192}") { [weak self] in self?.goForward() }
        back.contextFlyout = backMenu
        forward.contextFlyout = forwardMenu
        backMenu.opening.addHandler { [weak self] _, _ in self?.openHistoryMenu(.back) }
        forwardMenu.opening.addHandler { [weak self] _, _ in self?.openHistoryMenu(.forward) }
        toolbar.children.append(back)
        toolbar.children.append(forward)
        let reload = UI.button("\u{27F3}") { [weak self] in self?.shownPage?.reload() }
        for (i, group) in ReloadMenuItems.groups.enumerated() {
            if i > 0 { reloadMenu.items.append(MenuFlyoutSeparator()) }
            for id in group {
                let title = WinKeyBindings.shared.action(id)?.name ?? id
                reloadMenu.items.append(UI.menuItem(title, action: id) { [weak self] in _ = self?.perform(id) })
            }
        }
        reload.contextFlyout = reloadMenu
        toolbar.children.append(reload)
        // Arc's narrow header (under 212): ← → and •••, whose menu has Reload and Toggle Sidebar.
        let more = UI.button("\u{2022}\u{2022}\u{2022}") { [weak self] in
            guard let self, let more = self.headerButtons?.more else { return }
            try? self.headerMoreMenu.showAt(more)
        }
        ArcTip.set(more, "More options")
        try? AutomationProperties.setName(more, "More options")
        for (title, action) in [("Reload", "reload"), ("Toggle Sidebar", "toggleSidebar")] {
            let entry = MenuFlyoutItem()
            entry.text = title
            if let key = WinKeyBindings.shared.action(action)?.primary { entry.keyboardAcceleratorTextOverride = key.windowsDisplay }
            entry.click.addHandler { [weak self] _, _ in _ = self?.perform(action) }
            headerMoreMenu.items.append(entry)
        }
        toolbar.children.append(more)
        headerRow = toolbar
        headerButtons = (back, forward, reload, more)

        address.fontSize = 13
        address.textTrimming = .characterEllipsis
        address.text = "Search or enter address"
        addressButton = UI.button(address) { [weak self] in self?.openCommandBar(.editURL) }
        addressButton.horizontalAlignment = .stretch
        addressButton.horizontalContentAlignment = .left

        // Arc's URL pill: the address, then the sliders that open the Site Control Center.
        slidersGlyph.glyph = WinGlyph.code("slider.horizontal.3")
        slidersGlyph.fontSize = 13
        sliders = UI.button(slidersGlyph) { [weak self] in self?.toggleSiteControlCenter() }
        ArcTip.set(sliders, "Site Controls")
        try? AutomationProperties.setName(sliders, "Site Controls")
        let pill = Grid()
        pill.columnDefinitions.append(UI.column(UI.star))
        pill.columnDefinitions.append(UI.column(UI.auto))
        pill.columnDefinitions.append(UI.column(UI.auto))
        pill.margin = Thickness(left: 0, top: 8, right: 0, bottom: 8)
        pill.children.append(addressButton)
        try? Grid.setColumn(addressButton, 0)
        pillPins.orientation = .horizontal
        pill.children.append(pillPins)
        try? Grid.setColumn(pillPins, 1)
        pill.children.append(sliders)
        try? Grid.setColumn(sliders, 2)

        sidebarNavigation = [back, forward, reload, more, pill]
        let parts: [FrameworkElement] = [toolbar, pill, sidebar.root]
        for (i, part) in parts.enumerated() {
            sidebarPanel.children.append(part)
            try? Grid.setRow(part, Int32(i))
        }
        sidebarParts = parts
        // The Library over all three, from the window's top left (its rail runs to the edge).
        library.root.visibility = .collapsed
        library.root.margin = Thickness(left: -10, top: -10, right: -10, bottom: -10)
        sidebarPanel.children.append(library.root)
        try? Grid.setRowSpan(library.root, 3)

        // Shortcuts while the sidebar has the keyboard; the page reports its own (handleKey).
        sidebarPanel.keyDown.addHandler { [weak self] _, args in
            guard let self, let args, !args.handled else { return }
            let key = KeyPress(keyCode: Int32(truncatingIfNeeded: args.key.rawValue), control: Self.isDown(0x11),
                               shift: Self.isDown(0x10), alt: Self.isDown(0x12))
            if self.tabSwitcher?.isOpen == true ? self.switcherKey(key) : self.handleShortcut(key) { args.handled = true }
        }
        return sidebarPanel
    }

    private static func isDown(_ virtualKey: Int32) -> Bool { GetKeyState(virtualKey) < 0 }

    /// The page area in physical pixels, relative to the window's client area.
    private func contentFrame() -> PixelRect {
        window?.contentFrame ?? PixelRect(x: Int32(tabSidebarWidth), y: 0, width: 800, height: 600)
    }

    // MARK: Address and command bar

    private func showAddress(_ url: String) {
        address.text = url.isEmpty ? "Search or enter address" : SuggestionEngine.humanURL(url)
        address.foreground = url.isEmpty ? sidebar.secondaryTextColor : sidebar.textColor
        slidersGlyph.foreground = sidebar.secondaryTextColor
        syncPillPins()
    }

    /// The pill's pinned extensions while the toolbar is hidden (Arc 1.171, GitHub #226): the
    /// page's profile's pins before the sliders, while they leave the address its room
    /// (ToolbarComposition.urlFieldAccessories); more than fit show none there.
    private func syncPillPins(reload: Bool = true) {
        if reload { pillPinsAll = toolbarPins(scale: window?.scale ?? 1) }
        let pins = pillPinsAll
        let fitting = ToolbarComposition.urlFieldAccessories(pinnedExtensions: pins.map(\.id),
                                                             fieldWidth: CGFloat(tabSidebarWidth - 20))
        let shown = pins.filter { fitting.contains(.pinnedExtension($0.id)) }
        guard shown != pillPinsShown else { return }
        pillPinsShown = shown
        pillPins.children.clear()
        pillPinButtons = [:]
        for pin in shown {
            let content: UIElement
            if let icon = pin.icon {
                content = UI.image(icon, size: 16)
            } else {
                let piece = FontIcon()
                piece.glyph = WinGlyph.code("puzzlepiece.extension")
                piece.fontSize = 13
                piece.foreground = sidebar.secondaryTextColor
                content = piece
            }
            let id = pin.id
            // The popup hangs from the pin.
            let b = UI.button(content, padding: Thickness(left: 6, top: 5, right: 6, bottom: 5)) { [weak self] in
                guard let self else { return }
                self.runExtension(id, anchor: self.pillPinButtons[id].map { ($0, false) })
            }
            pillPinButtons[id] = b
            ArcTip.set(b, pin.name)
            try? AutomationProperties.setName(b, pin.name)
            pillPins.children.append(b)
        }
    }

    /// Keys to the page shown, else the sidebar.
    /// The keyboard to the page on screen; while the Library is open, to its search (the window
    /// coming back to the front, a space changing), so Escape and typing reach it.
    private func focusContent() {
        if libraryPage != nil {
            window.focusXAML()
            library.focusSearch()
        } else if let page = shownPage {
            page.setFocused(true)
        } else {
            focusSidebar()
        }
    }

    /// Keys to the sidebar's XAML, so its shortcuts work with no page to take them. Right after
    /// launch the XAML isn't laid out yet and the focus doesn't take: a window that opened on a
    /// space with no tab selected took no keys, Ctrl+T included, until it was clicked. Then it's
    /// tried again every 50 ms for up to a second, while the window is in front with nothing else
    /// to take the keyboard.
    private func focusSidebar() {
        try? sidebarFocusRetry?.stop()
        sidebarFocusRetry = nil
        window.focusXAML()
        if focusSidebarControl() { return }
        var tries = 0
        let timer = try? dispatcher.createTimer()
        timer?.interval = TimeSpan(duration: 50 * 10_000)
        timer?.isRepeating = true
        timer?.tick.addHandler { [weak self] _, _ in
            guard let self else { return }
            tries += 1
            let inFront = GetForegroundWindow() == HWND(bitPattern: self.hwnd)
            guard tries <= 20, inFront, !self.closing, self.shownPage == nil, self.libraryPage == nil,
                  !self.commandBar.isOpen else {
                try? self.sidebarFocusRetry?.stop()
                self.sidebarFocusRetry = nil
                return
            }
            self.window.focusXAML()
            if self.focusSidebarControl() {
                try? self.sidebarFocusRetry?.stop()
                self.sidebarFocusRetry = nil
            }
        }
        sidebarFocusRetry = timer
        try? timer?.start()
    }

    /// The address pill, or the sidebar button while the toolbar has the address.
    private func focusSidebarControl() -> Bool {
        // The pill is the last of the parts the toolbar takes over.
        if sidebarNavigation.last?.visibility != .collapsed, (try? addressButton.focus(.programmatic)) == true {
            return true
        }
        return (try? sidebarToggle.focus(.programmatic)) == true
    }

    private func makeCommandBar() {
        commandBar.onCommit = { [weak self] row, typed, mode in self?.handleCommit(row, typed: typed, mode: mode) }
        commandBar.onOpenInBackground = { [weak self] row, typed in self?.openInBackground(row, typed: typed) ?? false }
        commandBar.onOpenInSplit = { [weak self] row, typed in self?.openInSplit(row, typed: typed) ?? false }
        // The search-suggestions notice: Search Settings… is Settings ▸ Profiles (the engine), "here" Cra's privacy page.
        commandBar.onNoticeSettings = { [weak self] in self?.openSettings(pane: .profiles) }
        commandBar.onNoticeLearnMore = { [weak self] in
            guard let self else { return }
            self.store.createTab(url: SearchSuggestionsNotice.privacyPage, window: self.windowID)
        }
        commandBar.onResize = { [weak self] height in
            self?.commandBarHeight = height
            self?.placeCommandBar()
        }
        commandBar.onClose = { [weak self] in
            guard let self else { return }
            self.commandWindow?.hide()
            // Back to the page, unless another window took the front. Hiding the bar doesn't
            // always hand the front back to this window by itself.
            guard !self.commandBarDeactivated else { return }
            if let window = HWND(bitPattern: self.hwnd) { _ = SetForegroundWindow(window) }
            self.focusContent()
        }
        do {
            commandWindow = try FloatingWindow(owner: window, content: commandBar.root)
            commandWindow?.onDeactivate = { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                self.commandBarDeactivated = true
                self.commandBar.close()
            }
        } catch {
            print("The command bar's window could not be made: \(error)")
        }
    }

    /// Ctrl+T (`newTab`) or Ctrl+L (`editURL`): the bar over the page, as MainWindowController opens it.
    /// After the event that asks for it: its window taking the front inside a click handler (a
    /// press-mode button) or a page's key callback would take the rest of that input with it.
    func openCommandBar(_ mode: CommandBarMode) {
        _ = try? dispatcher.tryEnqueue { [weak self] in self?.presentCommandBar(mode) }
    }

    /// A link from another app soon after starting on a new tab: its tab is what the window
    /// shows, so the bar waiting for a new tab goes (the Mac's openExternalURL).
    func closeNewTabBar() {
        if commandBar.isOpen, store.selectedTab(window: windowID) == nil { commandBar.close() }
    }

    /// cra://commandbar: the bar, with `query` typed into it. With the bar already open a new
    /// query is the next keystroke, not a new session (AppDelegate.handleInternalURL).
    func openCommandBar(_ mode: CommandBarMode, query: String?) {
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { return }
            if !(self.commandBar.isOpen && query != nil) { self.presentCommandBar(mode) }
            if let query { self.commandBar.setQuery(query) }
        }
    }

    /// cra://dismiss: whatever transient UI is up closes (MainWindowController.dismissTransientUI).
    func dismissTransientUI() {
        guard !closing else { return }
        commandBar.close()
        hideFindBar()
        hideSiteControlCenter()
    }

    private func presentCommandBar(_ mode: CommandBarMode) {
        guard !closing, let commandWindow else { return }
        // An empty pane gets Arc's "Search or Enter URL…" bar; the result fills the pane.
        let fillingEmptyPane = store.selectedTab(window: windowID)?.isEmptyTab == true
        let prefill = mode == .editURL && !fillingEmptyPane ? store.selectedTab(window: windowID)?.tab?.url : nil
        let effective: CommandBarMode = mode == .editURL && (store.selectedTab(window: windowID) == nil || fillingEmptyPane) ? .newTab : mode
        commandBarDeactivated = false
        commandBar.open(mode: effective, prefill: prefill, theme: store.focusedSpace(window: windowID).theme)
        placeCommandBar()
        commandWindow.show { [weak self] in self?.commandBar.focusField() }
    }

    /// Centred on the window, the field where a full bar would put it, so rows coming and going
    /// don't move what you type into (MainWindowController.positionCommandPanel).
    private func placeCommandBar() {
        guard let commandWindow, commandBar.isOpen, let window else { return }
        let scale = window.scale
        let position = window.appWindow.position, size = window.appWindow.size
        let width = min(CommandBarView.width, Double(size.width) / scale - 80) * scale
        let fullHeight = CommandBarView.height(forRows: SuggestionEngine.maxRows) * scale
        let top = Double(position.y) + Double(size.height) / 2 - fullHeight / 2 - 40 * scale
        let left = Double(position.x) + (Double(size.width) - width) / 2
        commandWindow.place(origin: PointInt32(x: Int32(left.rounded()), y: Int32(top.rounded())),
                            size: SizeInt32(width: Int32(width.rounded()), height: Int32((commandBarHeight * scale).rounded())))
    }

    /// What Return in the bar does (MainWindowController.handleCommit).
    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode) {
        let query = commandBar.query
        func open(_ url: String) {
            store.recordQuerySelection(query: query, url: url)
            let fillsEmptyPane = store.selectedTab(window: windowID)?.isEmptyTab == true
            if mode == .editURL || fillsEmptyPane, store.selectedTabID(window: windowID) != nil {
                loadInSelectedTab(url)
            } else if !isIncognito, let space = store.settings.space(forTypedURL: url), space != store.focusedSpaceID(window: windowID),
                      store.orderedSpaces.contains(where: { $0.id == space }) {
                // Air Traffic Control routes a typed URL too (upstream #421): the tab opens in the
                // route's space and the window goes there, as in Arc.
                store.createTab(url: url, in: space, window: windowID)
            } else {
                store.createTab(url: url, window: windowID)
            }
        }
        guard let s else {
            if typed.isEmpty { return }
            open(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : engine.searchURL(typed))
            return
        }
        switch s.kind {
        case .switchToTab(let id):
            store.recordQuerySelection(query: query, url: s.url ?? "")
            store.selectTab(id, window: windowID)
        case .archived(let id):
            _ = store.restoreArchived(id)
        case .navigate:
            open(typed == query ? (s.url ?? SuggestionEngine.urlFromInput(typed)) : SuggestionEngine.urlFromInput(typed))
        case .search:
            open(s.url ?? engine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "")
        case .command(let id):
            perform(id)
        case .switchSpace(let id):
            store.focusSpace(id, window: windowID)
        case .moveToSpace(let id):
            if let t = store.selectedTabID(window: windowID) { _ = store.moveTabAndFollow(t, toSpace: id, window: windowID) }
        case .moveToFolder(let id):
            if let t = store.selectedTabID(window: windowID) { store.moveItem(t, to: id, index: nil) }
        }
    }

    /// Ctrl+Return in the bar (Arc's ⌘Return): the row's page in a new background tab, the bar
    /// staying open; an open tab's row opens its address again rather than switching.
    private func openInBackground(_ s: Suggestion?, typed: String) -> Bool {
        let query = commandBar.query, engine: SuggestionEngine = engine
        guard let url = CommandBarRowPage.url(row: s, typed: typed, query: query, searchURL: { engine.searchURL($0) })
        else { return false }
        store.recordQuerySelection(query: query, url: url)
        let tab = store.createTab(url: url, select: false, window: windowID)
        store.markUnread(tab.id, false)  // Arc saves these read, unlike a link opened in the background
        return true
    }

    /// Alt+Return in the bar (Arc's ⌥Return): the row opens as a split pane beside the current tab,
    /// an open tab of this space joining the split (`SidebarStore.openInSplit`, the Mac's too).
    /// False takes it as Return.
    private func openInSplit(_ s: Suggestion?, typed: String) -> Bool {
        let engine: SuggestionEngine = engine
        switch store.openInSplit(s, typed: typed, query: commandBar.query, current: store.selectedTabID(window: windowID),
                                 window: windowID, searchURL: { engine.searchURL($0) }) {
        case .asReturn: return false
        case .full: showToast("Cannot Add New Pane")
        case .joined: break
        case .addedPane: refresh()
        }
        return true
    }

    /// `url` in the selected tab (cra://navigate, and the command bar's Edit URL).
    func loadInSelectedTab(_ url: String) {
        guard let id = store.selectedTabID(window: windowID) else { return }
        if let page = pages[id] {
            page.loadURL(url)
            page.setFocused(true)
        } else {
            // An empty tab: its first page.
            store.updateTab(id, url: url)
        }
    }

    /// An action by its id (KeyBindingDefaults.windows): a command row or a shortcut. False
    /// for an id the Windows app doesn't perform yet.
    @discardableResult
    func perform(_ id: String) -> Bool {
        switch id {
        case "find": showFindBar()
        case "findNext": findNext(forward: true)
        case "findPrevious": findNext(forward: false)
        case "useSelectionForFind": useSelectionForFind()
        case "jumpToSelection": shownPage?.jumpToSelection()
        case "savePageAs":
            if let page = shownPage {
                page.savePageAs(owner: hwnd, title: store.selectedTab(window: windowID)?.displayTitle ?? "") { [weak self] in self?.showToast($0) }
            }
        case "settings": openSettings()
        case "essentialShortcuts": showEssentialShortcuts()
        // Chrome's own Task Manager and Cast dialogs, on the page in front (the Mac's runChromeCommand).
        case "taskManager": if shownPage?.runChromeCommand("IDC_TASK_MANAGER") != true { showToast("Open a Page First") }
        case "cast": if shownPage?.runChromeCommand("IDC_ROUTE_MEDIA") != true { showToast("Nothing to Cast") }
        // Arc's Open Extensions (⌘E on the Mac): the Site Control Center, its extension tiles.
        case "openExtensions": toggleSiteControlCenter()
        case "manageExtensions": store.createTab(url: SiteControlCenter.manageExtensionsURL, window: windowID)
        case "setDefaultBrowser": DefaultBrowser.makeDefault()
        case "importData": if !isIncognito { showImportDialog() }
        // Chrome's Delete browsing data dialog; what it deletes from history leaves the command bar.
        case "clearBrowsingData": if !isIncognito { store.createTab(url: BrowsingDataClear.pageURL, window: windowID) }
        case "newWindow": host?.openNewWindow(incognito: false)
        case "newIncognitoWindow": host?.openNewWindow(incognito: true)
        case "newLittleWindow": host?.newLittleWindow()
        case "closeLittleWindows": host?.closeLittleWindows()
        case "closeWindow": requestClose()
        case "changeProfile": if !isIncognito { showChangeProfile(forSpace: store.focusedSpaceID(window: windowID)) }
        case "newProfile": if !isIncognito { showNewProfile(ticked: []) }
        case "rebuildArcProfiles": if !isIncognito { rebuildArcProfiles() }
        case "share":
            if let tab = store.selectedTab(window: windowID), let url = tab.tab?.url, !url.isEmpty {
                share(url: url, title: tab.displayTitle)
            }
        case "newTab": beginNewTab()
        case "editURL": openCommandBar(.editURL)
        case "reopenClosedTab": reopenClosedTab()
        case "openLibrary": toggleLibrary()
        case "toggleSidebar": toggleSidebar()
        case "viewArchive": showLibrary(.archive)
        // Ctrl+J is a show/hide toggle like Open Library, as in Arc (LibraryShortcut, #649); the
        // other pages' commands only show their page.
        case "viewDownloads": toggleLibrary(.downloads)
        case "manageSpaces": if !isIncognito { showLibrary(.spaces) }
        // Edit Space…: Arc's theme editor beside the sidebar (Windows has no Edit Space sheet yet).
        case "editSpace": if !isIncognito { sidebar.showStyleEditor(space: store.focusedSpaceID(window: windowID)) }
        case "deleteSpace": if !isIncognito { confirmDeleteSpace(store.focusedSpaceID(window: windowID)) }
        case "closeTab": closeCurrentTab()
        case "reload": reload(ignoringCache: false)
        case "stop": shownPage?.stopLoading()
        case "toggleToolbar": store.settings.showToolbar.toggle()
        case "hardReload": reload(ignoringCache: true)
        case "pinTab": if let t = store.selectedTabID(window: windowID) { store.togglePinned(t) }
        case "renameTab": renameSelectedTab()
        case "duplicateTab": if let t = store.selectedTabID(window: windowID), store.item(t)?.isTab == true { _ = store.duplicateTab(t) }
        case "muteTab": if let t = store.selectedTabID(window: windowID), store.item(t)?.isTab == true { toggleMute(t) }
        case "pictureInPicture": shownPage?.togglePictureInPicture()
        case "pauseAllMedia": host?.pauseAllMedia { [weak self] text, action in self?.showToast(text, action: action) }
        case "resetTab": if let t = store.selectedTabID(window: windowID) { resetPinnedTab(t) }
        case "newFolder": sidebar.newFolder()
        case "newSpace": if !isIncognito { sidebar.newSpace() }
        case "clearToday": store.clearToday(store.focusedSpaceID(window: windowID), playing: sidebar.audibleTabIDs)
        case "showArchive": showLibrary(.archive)
        case "clearArchive": store.clearArchive()
        case "revealData": Shell.open(WinPaths.native(WinPaths.supportDir))
        case "copyAppInfo":
            let engine = EngineVersion.label(chromium: String(cString: cra_cef_chromium_version()), cef: String(cString: cra_cef_version()))
            if WinShell.copy(CraInfo.text(app: CraInfo.appLine(version: WinShell.appVersion), engine: engine, system: WinVersion.line)) {
                showToast("Copied Cra Info")
            }
        // Chromium's page edits the profile of the space it opens in, so not a private window's.
        case "languageSettings": if !isIncognito { store.createTab(url: BrowserLanguages.settingsPage, window: windowID) }
        case "appearanceAutomatic", "appearanceLight", "appearanceDark":
            if let appearance = WebsiteAppearance(commandID: id) { store.settings.websiteAppearance = appearance }
        case "resetSpaceTabs": resetAllPinnedTabs()
        case "favoriteTab": if let t = store.selectedTabID(window: windowID), !store.isFavorite(t) { store.addToFavorites(t) }
        case "recentTab": cycleRecentTabs(1)
        case "recentTabBackward": cycleRecentTabs(-1)
        case "recentTabAllSpaces": cycleRecentTabs(1, allSpaces: true)
        case "recentTabAllSpacesBackward": cycleRecentTabs(-1, allSpaces: true)
        case "nextTab": cycleTab(1)
        case "previousTab": cycleTab(-1)
        case "nextSpace": store.focusSpace(offset: 1, window: windowID)
        case "previousSpace": store.focusSpace(offset: -1, window: windowID)
        case "copyURL": copyURL(markdown: false)
        case "copyURLMarkdown": copyURL(markdown: true)
        case "copyURLQuote": copyURLAsQuote()
        case "pasteAndGo": pasteAndGo()
        case "stayOnTop": window.staysOnTop.toggle()
        case "capturePage": capture(fullPage: false)
        case "captureFullPage": capture(fullPage: true)
        case "clearCache": shownPage?.clearSiteDataAndReload(cookies: false)
        case "clearCookies": shownPage?.clearSiteDataAndReload(cookies: true)
        case "devTools": shownPage?.runDevTools(.toggle)
        case "jsConsole": shownPage?.runDevTools(.console)
        case "inspectElement": shownPage?.runDevTools(.inspect)
        case "networkPanel": shownPage?.runDevTools(.network)
        case "toggleDeveloperMode": toggleDeveloperMode()
        case "goBack": goBack()
        case "goForward": goForward()
        // The Mac's steps (MainWindowController.zoom(by:)): half a Chromium zoom level, which
        // Chromium keeps for the site.
        case "zoomIn": if let page = shownPage { page.zoomLevel += 0.5 }
        case "zoomOut": if let page = shownPage { page.zoomLevel -= 0.5 }
        case "resetZoom": shownPage?.zoomLevel = 0
        case "print": shownPage?.printPage()
        case "viewSource": shownPage?.viewSource()
        case "addSplitView": addSplitPane()
        case "closeSplitPane": if let t = store.selectedTabID(window: windowID) { closeSplitPane(t) }
        case "separateFromSplit": if let t = store.selectedTabID(window: windowID) { separatePane(t) }
        case "flipSplitOrientation": if let t = store.selectedTabID(window: windowID), let split = store.splitContaining(t) { store.flipSplitOrientation(split.id) }
        case "nextSplitPane": cycleSplitPane(1)
        case "previousSplitPane": cycleSplitPane(-1)
        case "expandSplitPane": if let t = store.selectedTabID(window: windowID) { expandSplitPane(t) }
        // Arc's sidebar commands; the store does the work and the sidebar redraws.
        case "collapsePinned": store.togglePinnedCollapsed(store.focusedSpaceID(window: windowID))
        case "collapseAllFolders": store.setAllFoldersExpanded(false, inSpace: store.focusedSpaceID(window: windowID))
        case "expandAllFolders": store.setAllFoldersExpanded(true, inSpace: store.focusedSpaceID(window: windowID))
        case "revealTab": revealSelectedTab()
        default:
            if id.hasPrefix("space"), let n = Int(id.dropFirst(5)), (1...9).contains(n) {
                store.focusSpace(number: n, window: windowID)
                return true
            }
            // Move Tab to Space N: the open tab (its split, if any) goes there and the window follows.
            // An incognito window's tabs stay in it, as its tab menu has no Move to Space.
            if id.hasPrefix("moveTabToSpace"), let n = Int(id.dropFirst(14)), (1...9).contains(n) {
                if let t = store.selectedTabID(window: windowID), !store.isIncognito(item: t), n <= store.spaceOrder.count {
                    _ = store.moveTabAndFollow(t, toSpace: store.spaceOrder[n - 1], window: windowID)
                }
                return true
            }
            if id.hasPrefix("splitPane"), let n = Int(id.dropFirst(9)), (1...4).contains(n) {
                store.selectSplitPane(n, window: windowID)
                return true
            }
            guard id.hasPrefix("item"), let n = Int(id.dropFirst(4)), (1...9).contains(n) else { return false }
            selectTab(number: n)
        }
        return true
    }

    // MARK: Commands

    /// Rename Tab…: the open tab's row takes a field. A pane has no row of its own, so its split's
    /// name is edited (the Mac's renameTab); a favorite draws as a tile, with no name to edit there.
    private func renameSelectedTab() {
        guard let t = store.selectedTabID(window: windowID) else { return }
        let row = store.splitContaining(t)?.id ?? t
        guard !store.isFavorite(row) else { return }
        sidebar.beginRename(item: row)
    }

    private func closeCurrentTab() {
        if let id = store.selectedTabID(window: windowID) { closeTab(id) }
    }

    // MARK: Tab sleeping

    /// When each page went out of sight (TabSleepPolicy's hiddenAt).
    private func noteHidden(shown: Set<UUID>) {
        let now = Date()
        for id in pages.keys {
            if shown.contains(id) { hiddenAt[id] = nil } else if hiddenAt[id] == nil { hiddenAt[id] = now }
        }
        hiddenAt = hiddenAt.filter { pages[$0.key] != nil }
        sleepAskAfter = sleepAskAfter.filter { pages[$0.key] != nil }
    }

    private func startTabSleeping() {
        sleepTimer = try? dispatcher.createTimer()
        sleepTimer?.interval = TimeSpan(duration: Int64(TabSleepPolicy.passInterval * 10_000_000))
        sleepTimer?.isRepeating = true
        sleepTimer?.tick.addHandler { [weak self] _, _ in self?.sleepIdleTabs() }
        try? sleepTimer?.start()
    }

    /// Settings ▸ Tabs ▸ Free memory from unused tabs: a page out of sight longer than the
    /// setting (Arc's 4 hours), and not one of the 10 tabs used last, closes and loads again
    /// when its tab is shown. Pages that are loading or in DevTools stay; so do pages holding
    /// edited fields, playing sound or asking before they close (TabSleepProbe), which are
    /// asked again after 10 minutes. Windows' CEF can't discard a page and keep its history, so
    /// the tab reloads its address.
    private func sleepIdleTabs() {
        let settings = store.settings
        guard !closing, settings.tabSleepTimerEnabled else { return }
        let policy = TabSleepPolicy.timer(settings.tabSleepAfter)
        let now = Date()
        let cutoff = now.addingTimeInterval(-policy.hiddenFor)
        let visible = paneIDs
        // "Always keep these sites active" (#458): a listed site's page never sleeps on the timer.
        let list = pages.map { id, page in
            TabSleepPolicy.Page(id: id, hiddenAt: hiddenAt[id], keptActive: settings.keepsActive(url: page.currentURL))
        }
        for id in policy.candidates(list, visible: visible, now: now) {
            guard let page = pages[id], sleepAskAfter[id].map({ $0 <= now }) ?? true else { continue }
            let state = TabSleepPolicy.PageState(hiddenAt: hiddenAt[id], visible: visible.contains(id), created: page.isCreated,
                                                 loading: page.isLoading, devTools: page.hasDevTools)
            guard TabSleepPolicy.hold(state, before: cutoff) == nil else { continue }
            page.sendDevToolsMethod("Runtime.evaluate", params: TabSleepProbe.evaluateParams) { [weak self, weak page] reply, error in
                guard let self, let page, self.pages[id] === page, !self.paneIDs.contains(id),
                      self.hiddenAt[id].map({ $0 < cutoff }) == true else { return }
                let refusal = error == nil ? TabSleepProbe.refusal(fromReply: reply) : "no reply"
                guard refusal.isEmpty else {
                    self.sleepAskAfter[id] = Date().addingTimeInterval(Self.sleepRefusalBackoff)
                    return
                }
                self.pages[id] = nil
                self.hiddenAt[id] = nil
                self.sleepAskAfter[id] = nil
                page.close()
            }
        }
    }

    private static let sleepRefusalBackoff: TimeInterval = 10 * 60

    // MARK: Sound

    private func startAudibleProbe() {
        setUpNowPlaying()
        audibleTimer = try? dispatcher.createTimer()
        audibleTimer?.interval = TimeSpan(duration: Int64(AudibleProbe.Tracker.pollInterval * 10_000_000))
        audibleTimer?.isRepeating = true
        audibleTimer?.tick.addHandler { [weak self] _, _ in self?.probeAudible() }
        try? audibleTimer?.start()
    }

    /// Arc's speaker on a tab that plays sound (TabSound, #28): each live page says whether a
    /// player in it can be heard, and the speaker holds 2 s after it stops (as on the Mac).
    private func probeAudible() {
        guard !closing else { return }
        audible.keep(only: Set(pages.keys))
        nowPlaying.keep(only: Set(pages.keys))
        showAudible()
        syncNowPlaying()
        for (id, page) in pages where page.isCreated {
            page.sendDevToolsMethod("Runtime.evaluate", params: AudibleProbe.evaluateParams) { [weak self, weak page] reply, error in
                guard let self, let page, self.pages[id] === page, !self.closing else { return }
                let answer = error == nil ? AudibleProbe.answer(fromReply: reply) : nil
                self.audible.note(id, audible: answer?.audible, now: Date())
                if let answer { self.nowPlaying.heard(id, answer) }
                self.showAudible()
                self.syncNowPlaying()
            }
        }
    }

    /// The player's cards: tabs that played sound and aren't on screen, with the page's own title.
    private func syncNowPlaying() {
        let cards = nowPlaying.shown(onScreen: Set(paneIDs)).compactMap { entry -> NowPlayingTray.Card? in
            guard let item = store.item(entry.id), let tab = item.tab else { return nil }
            return .init(id: entry.id, title: tab.savedTitle.isEmpty ? item.displayTitle : tab.savedTitle,
                         iconKey: tab.iconKey, playing: entry.playing, hasVideo: entry.hasVideo)
        }
        nowPlayingTray.show(cards, dark: sidebar.isDark)
    }

    private func setUpNowPlaying() {
        nowPlayingTray.onRestingHeight = { [weak self] height in self?.sidebar.reserveBottom(height) }
        nowPlayingTray.onShowTab = { [weak self] id in
            guard let self else { return }
            self.store.selectTab(id, window: self.windowID)
        }
        nowPlayingTray.onTogglePlayback = { [weak self] id in self?.playback(id, .toggle) }
        nowPlayingTray.onPictureInPicture = { [weak self] id in self?.pages[id]?.requestPictureInPicture(automatic: false) }
        nowPlayingTray.onDismiss = { [weak self] id in
            guard let self else { return }
            self.playback(id, .pause)
            self.nowPlaying.remove(id)
            self.syncNowPlaying()
        }
    }

    /// The card's play/pause and ✕: the page's media elements, as the Mac's player runs a page
    /// without media session handlers.
    private func playback(_ id: UUID, _ op: NowPlayingList.Playback) {
        guard let page = pages[id] else {
            nowPlaying.remove(id)
            return syncNowPlaying()
        }
        page.sendDevToolsMethod("Runtime.evaluate", params: NowPlayingList.playbackParams(op)) { [weak self] reply, _ in
            guard let self, op == .toggle, let playing = NowPlayingList.playing(fromReply: reply) else { return }
            self.nowPlaying.setPlaying(id, playing)
            self.syncNowPlaying()
        }
    }

    private func showAudible() {
        let now = audible.audible(now: Date())
        guard now != sidebar.audibleTabIDs else { return }
        sidebar.audibleTabIDs = now
        queueRefresh()
    }

    // MARK: Tab switcher

    private func makeTabSwitcher() {
        guard let window else { return }
        tabSwitcher = TabSwitcherWindow(owner: window) { [weak window] in
            guard let window else { return nil }
            let position = window.appWindow.position, size = window.appWindow.size
            return (position.x, position.y, size.width, size.height, window.scale)
        }
        tabSwitcher.onCommit = { [weak self] id in
            guard let self, id != self.store.selectedTabID(window: self.windowID) else { return }
            self.store.selectTab(id, window: self.windowID)
        }
    }

    /// Ctrl+Tab / Ctrl+Shift+Tab: Arc's switcher over the space's recent tabs
    /// (MainWindowController.cycleRecentTabs).
    /// `allSpaces`: the Mac's ⌃⌥Tab (#467), every space's recent tabs, each card naming its space
    /// (MainWindowController.tabSwitcherItems). Picking one goes to its space.
    private func cycleRecentTabs(_ delta: Int, allSpaces: Bool = false) {
        let space = store.focusedSpace(window: windowID)
        let selected = store.selectedTabID(window: windowID)
        tabSwitcher.cycle(delta, theme: space.theme, dark: WinAppearance.isDark) {
            // A split is one card (#554): open when any pane is (MainWindowController.openRecentCards).
            let recent = TabSwitcherCycle.cards(allSpaces ? store.recentCardsInAllSpaces(limit: .max, window: windowID)
                                                              : store.recentCards(in: space.id, limit: .max, window: windowID),
                                                selected: selected,
                                                isPinned: { self.store.isPinned($0) }, isLoaded: { self.pages[$0] != nil })
            return recent.compactMap { card in
                guard let item = store.item(card.opens), let tab = item.tab else { return nil }
                var c = TabSwitcherWindow.Card(id: card.opens, title: item.displayTitle, iconKey: tab.iconKey)
                if allSpaces { c.spaceTitle = store.spaceID(ofItem: card.opens, window: windowID).flatMap(store.space)?.title }
                if card.isSplit {
                    let factors = SplitPaneLayout.normalizedFactors(ids: card.panes, stored: store.item(card.id)?.split?.widthFactors ?? [:])
                    c.panes = card.panes.map { (iconKey: store.item($0)?.tab?.iconKey, width: Double(factors[$0] ?? 1)) }
                }
                return c
            }
        }
    }

    /// Every key is the switcher's while it is up; the user's own switcher keys move it.
    private func switcherKey(_ key: KeyPress) -> Bool {
        let chord = KeyChord(windowsVirtualKey: key.keyCode, control: key.control, shift: key.shift, alt: key.alt)
        let direction: Int? = switch chord.flatMap({ WinKeyBindings.shared.action(matching: $0) })?.id ?? "" {
        case "recentTab", "recentTabAllSpaces": 1
        case "recentTabBackward", "recentTabAllSpacesBackward": -1
        default: nil
        }
        tabSwitcher.handle(key, direction: direction)
        return true
    }

    /// Selects the tab `delta` rows away in the space's favorites, pinned and Today tabs.
    private func cycleTab(_ delta: Int) {
        let tabs = store.visibleTabs(in: store.focusedSpaceID(window: windowID))
        guard !tabs.isEmpty else { return }
        let idx = store.selectedTabID(window: windowID).flatMap { id in tabs.firstIndex { $0.id == id } } ?? -1
        let n = tabs.count
        store.selectTab(tabs[((idx + delta) % n + n) % n].id, window: windowID)
    }

    /// Ctrl+1…8 the nth tab, Ctrl+9 the last (Arc's "Go to Sidebar Item N").
    private func selectTab(number n: Int) {
        let tabs = store.visibleTabs(in: store.focusedSpaceID(window: windowID))
        guard !tabs.isEmpty else { return }
        store.selectTab((n == 9 ? tabs.last : tabs[min(n, tabs.count) - 1])?.id, window: windowID)
    }

    // MARK: Library

    /// Arc's Library button and Ctrl+Shift+L: the Library on the page last shown, or back to the tabs.
    private func toggleLibrary() {
        if libraryPage == nil { showLibrary(lastLibraryPage) } else { closeLibrary() }
    }

    /// A page's shortcut: that page, or the Library closed when it shows that page already
    /// (MainWindowController.toggleLibrary(_:)).
    private func toggleLibrary(_ page: LibraryPage) {
        switch LibraryShortcut.step(requested: page, shown: libraryPage) {
        case .show: showLibrary(page)
        case .close: closeLibrary()
        }
    }

    private func setLibraryShown(_ open: Bool) {
        for part in sidebarParts { part.visibility = open ? .collapsed : .visible }
        library.root.visibility = open ? .visible : .collapsed
        syncLibraryWidth()
    }

    /// The sidebar's width for what it shows: the tabs, the Library 70 DIPs wider for its rail, or
    /// the Spaces page wide enough for every card while the window leaves the page 56 DIPs
    /// (LibraryWidth, the Mac's), its cards scrolling sideways past that. A window resize and a
    /// space added or removed size it again.
    private func syncLibraryWidth() {
        guard !closing, let window else { return }
        var width = tabSidebarWidth + (libraryPage != nil ? LibraryLayout.extraWidth : 0)
        if libraryPage != nil, let cards = library.spacesWidth {
            let windowWidth = Double(window.appWindow.clientSize.width) / window.scale
            width = max(width, LibraryWidth.sidebar(spacesCards: cards, window: windowWidth))
        }
        floatingSidebar?.width = width
        let column = sidebarDocked ? width : 0
        if window.sidebarWidth != column { window.sidebarWidth = column }
        placeSidebarEdge()
    }

    // MARK: Sidebar width

    /// Arc's drag of the sidebar's edge (#287, SidebarResize), as the Mac's MainWindowController
    /// runs it: the edge stays under the pointer, a slow drag snaps to 228 DIPs, and the sidebar
    /// hides under 82 and comes back at 164 if the drag returns before letting go. The width is
    /// saved for every window when the drag ends.
    private func wireSidebarEdge() {
        guard let sidebarEdge else { return }
        sidebarEdge.onBegin = { [weak self] in
            guard let self else { return }
            sidebarResize = SidebarResize(startWidth: tabSidebarWidth)
            hiddenByResize = false
        }
        sidebarEdge.onResize = { [weak self] translation, speed in
            guard let self, var resize = sidebarResize, !closing else { return }
            let outcome = resize.update(translation: translation, speed: speed)
            sidebarResize = resize
            switch outcome {
            case .hidden:
                // Hidden this way, it keeps the width the drag started from (Arc: Ctrl+S brings
                // back a 200 DIP sidebar dragged shut from 200).
                tabSidebarWidth = resize.startWidth
                if store.window(windowID).sidebarVisible {
                    store.chooseSidebar(visible: false, window: windowID)
                    hiddenByResize = true
                    syncSidebarMode()
                }
            case .width(let w):
                tabSidebarWidth = w
                if hiddenByResize {
                    hiddenByResize = false
                    store.chooseSidebar(visible: true, window: windowID)
                    syncSidebarMode()
                }
                syncLibraryWidth()
            }
        }
        sidebarEdge.onEnd = { [weak self] in
            guard let self, sidebarResize != nil else { return }
            sidebarResize = nil
            hiddenByResize = false
            if store.prefs.sidebarWidth != tabSidebarWidth { store.prefs.sidebarWidth = tabSidebarWidth }
            placeSidebarEdge()
            if store.window(windowID).sidebarVisible, shownPage != nil, !commandBar.isOpen { focusContent() }
        }
    }

    /// Settings ▸ Tabs ▸ Sidebar on the right (#464): the window in a mirror, the sidebar docked,
    /// floating and dragged from the right, the pages on the left.
    private func syncSidebarSide() {
        let side = store.settings.sidebarSide
        guard window.sidebarSide != side else { return }
        window.sidebarSide = side
        floatingSidebar?.side = side
        sidebarEdge?.side = side
        placeSidebarEdge()
    }

    /// Another window's drag changed the saved width: this one follows.
    private func syncSidebarWidth() {
        guard sidebarResize == nil else { return }
        let saved = SidebarResizeHandle.restored(store.prefs.sidebarWidth)
        guard saved != tabSidebarWidth else { return }
        tabSidebarWidth = saved
        syncLibraryWidth()
    }

    /// The strip over the docked sidebar's edge, the window's height; none while the sidebar is
    /// hidden, shows the Library, is under a Peek or the window is minimized (the Mac's
    /// `sidebarResizable`).
    private func placeSidebarEdge() {
        guard let sidebarEdge, !closing, let window, let host = HWND(bitPattern: hwnd) else { return }
        let scale = window.scale
        sidebarEdge.scale = scale
        // A Peek's veil and click catcher cover the sidebar: no resizing under them.
        let resizable = sidebarDocked && libraryPage == nil && !IsIconic(host) && window.sidebarWidth > 0
            && self.host?.hasPeek(over: self) != true
        guard resizable else { return sidebarEdge.place(x: 0, y: 0, width: 0, height: 0) }
        let strip = SidebarResizeHandle.strip(sidebarWidth: window.sidebarWidth)
        let clientWidth = Double(window.appWindow.clientSize.width) / scale
        let left = window.sidebarSide == .right ? clientWidth - strip.x - strip.width : strip.x
        var origin = POINT(x: Int32((left * scale).rounded()), y: 0)
        _ = ClientToScreen(host, &origin)
        sidebarEdge.place(x: origin.x, y: origin.y, width: Int32((strip.width * scale).rounded()),
                          height: window.appWindow.clientSize.height)
    }

    // MARK: Hidden sidebar

    private func makeFloatingSidebar() {
        floatingSidebar = FloatingSidebar(window: window, dispatcher: dispatcher)
        floatingSidebar.width = window.sidebarWidth
        floatingSidebar.presentation = { [weak self] in
            guard let self else { return SidebarPresentation(sidebarVisible: true, hasSelectedTab: true) }
            return SidebarPresentation(sidebarVisible: self.store.window(self.windowID).sidebarVisible,
                                       hasSelectedTab: self.store.selectedTab(window: self.windowID) != nil)
        }
        // The Library and a name being edited keep it out, as a folder's preview does on the Mac.
        floatingSidebar.keptOut = { [weak self] in
            guard let self else { return false }
            return self.libraryPage != nil || self.sidebar.renaming.itemID != nil || self.sidebar.renaming.spaceID != nil
        }
        floatingSidebar.onRetracted = { [weak self] in
            guard let self, !self.closing, !self.commandBar.isOpen else { return }
            // The keyboard was in the sidebar going out of sight: back to the page.
            if self.shownPage != nil, GetForegroundWindow() == HWND(bitPattern: self.hwnd) { self.focusContent() }
        }
    }

    /// Lays the column out for the window's choice (`WindowSession.sidebarVisible`): beside the
    /// pages, or hidden with the pages edge to edge and the floating sidebar watching the edge.
    private func syncSidebarMode() {
        let docked = store.window(windowID).sidebarVisible
        guard docked != sidebarDocked else { return }
        sidebarDocked = docked
        if docked { floatingSidebar.stop() }
        syncLibraryWidth()
        if !docked { floatingSidebar.start() }
    }

    /// Arc's Hide Sidebar (Ctrl+S): the window's sidebar hides or docks again, and new windows
    /// open the way it is now (#644). A sidebar that is out docks where it is.
    private func toggleSidebar() {
        let visible = store.window(windowID).sidebarVisible
        store.chooseSidebar(visible: !visible, window: windowID)
        refresh()
        if visible, shownPage != nil { focusContent() }
    }

    /// Arc's Restore Last Closed Tab (Ctrl+Shift+T): the tab closed last, whether a pinned tab
    /// (back at the page it was on, #566), an archived tab or a closed Peek, and with Settings ▸
    /// Tabs' "Reopen tabs from this Space only" only one closed in this space (#601). The order is
    /// CraCore's (`SidebarStore.reopenLastClosed`, ReopenClosedTab), as on the Mac.
    private func reopenClosedTab() {
        guard !isIncognito else { return }  // private tabs leave nothing to restore
        let peek = closedPeek.map { ReopenClosedTab.ClosedPeek(url: $0.url, tabID: $0.tabID, closedAt: $0.at) }
        let outcome = store.reopenLastClosed(in: windowID, peek: peek)
        if case .pinned(let id, _, _, let panes)? = outcome {
            // The store put the panes back on the pages they were on; pages already loaded (none,
            // normally: closing unloaded them) follow it.
            for p in panes.map(\.id) + [id] { if let url = store.item(p)?.tab?.url { pages[p]?.loadURL(url) } }
        }
        guard case .peek(let url, let tabID)? = outcome else { return }
        closedPeek = nil
        if let tabID, store.item(tabID) != nil { store.selectTab(tabID, window: windowID) }
        // Once the key's event is over and the redraw that selection queued has run: either
        // could hand the keyboard to this window's page after the card took it, and Escape
        // then never reached the Peek (seen on the PC after a Peek came back).
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { return }
            self.host?.openPeek(url: url, over: self, fromTab: tabID)
        }
    }

    // MARK: Peek

    /// Where a Peek over this window goes now (its client area on screen, the sidebar's width).
    func peekPlacement() -> PeekPlacement? {
        guard !closing, let host = HWND(bitPattern: hwnd) else { return nil }
        var origin = POINT(x: 0, y: 0)
        _ = ClientToScreen(host, &origin)
        let size = window.appWindow.clientSize
        return PeekPlacement(client: PixelRect(x: origin.x, y: origin.y, width: size.width, height: size.height),
                             sidebar: window.sidebarWidth, side: window.sidebarSide, scale: window.scale)
    }

    /// Arc badges the tab a Peek came from with the peeked page's favicon.
    func showPeekBadge(tab id: UUID?, url: String) {
        sidebar.peekBadge = id.map { ($0, FaviconKey.key(for: url)) }
        queueRefresh()
    }

    private func repositionPeeks() {
        host?.repositionPeeks(over: self)
    }

    // MARK: Find in page

    private func makeFindBar() {
        findBar.onFind = { [weak self] query, forward in self?.find(query, forward: forward) }
        findBar.onClose = { [weak self] in self?.hideFindBar() }
        do {
            findWindow = try FloatingWindow(owner: window, content: findBar.root)
            findWindow?.onClose = { [weak self] in self?.hideFindBar() }
        } catch {
            print("The find bar's window could not be made: \(error)")
        }
    }

    /// Ctrl+F (MainWindowController.showFindBar): the bar, its field focused.
    private func showFindBar() {
        guard !closing, let findWindow else { return }
        findBar.apply(dark: store.focusedSpace(window: windowID).theme.isDark)
        findVisible = true
        placeFindBar()
        // After the key event that asked, as with the command bar.
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, self.findVisible else { return }
            findWindow.show { [weak self] in self?.findBar.focusField() }
        }
    }

    private func hideFindBar() {
        guard findVisible else { return }
        findVisible = false
        findBar.reset()
        shownPage?.stopFinding(clearSelection: true)
        let front = UInt(bitPattern: GetForegroundWindow())
        let ours = front == findWindow?.hwnd || front == hwnd
        findWindow?.hide()
        guard !closing, ours else { return }
        // Typing goes back to the page, unless another app came to the front meanwhile. Again
        // once the click on ✕ is done with: XAML handing the press back to its button left the
        // hidden bar's window in front, with the keyboard.
        let restore = { [weak self] in
            guard let self, !self.findVisible, let window = HWND(bitPattern: self.hwnd) else { return }
            _ = SetForegroundWindow(window)
            self.focusContent()
        }
        restore()
        _ = try? dispatcher.tryEnqueue(restore)
    }

    /// Ctrl+G, Ctrl+Shift+G, F3: the next or previous match; opens the bar first.
    private func findNext(forward: Bool) {
        guard findVisible else { return showFindBar() }
        find(findBar.query, forward: forward)
    }

    /// Edit ▸ Find ▸ Use Selection to Find (MainWindowController.useSelectionForFind): the
    /// page's selection becomes the search, and the bar shows it found.
    private func useSelectionForFind() {
        guard let page = shownPage else { return }
        page.sendDevToolsMethod("Runtime.evaluate", params: FindSelection.evaluateParams) { [weak self, weak page] reply, _ in
            guard let self, let page, page === self.shownPage, !self.closing,
                  let query = FindSelection.query(fromReply: reply) else { return }
            let needsSearch = FindSelection.needsSearch(selection: query, barQuery: self.findBar.query)
            self.findBar.setQuery(query)  // a changed field searches as typing does
            self.showFindBar()
            if needsSearch { self.find(query, forward: true) }
        }
    }

    /// Always a follow-up find: CEF restarts the search when the text changes, and unlike a first
    /// request that selects a match, so the bar shows "1/3" rather than "0/3" (as on the Mac).
    private func find(_ query: String, forward: Bool) {
        guard let page = shownPage else { return }
        if query.isEmpty {
            findBar.reset()
            page.stopFinding(clearSelection: true)
            return
        }
        page.find(query, forward: forward, matchCase: false, findNext: true)
    }

    /// The top right of the page area, 10 DIPs in.
    private func placeFindBar() {
        guard findVisible, let findWindow, let window, let host = HWND(bitPattern: hwnd) else { return }
        let scale = window.scale, frame = shownTabID.flatMap { paneFrames[$0] } ?? window.contentFrame
        let width = (FindBarView.width * scale).rounded(), height = (FindBarView.height * scale).rounded()
        let inset = (FindBarView.inset * scale).rounded()
        var corner = POINT(x: frame.x + frame.width, y: frame.y)
        _ = ClientToScreen(host, &corner)
        findWindow.place(origin: PointInt32(x: corner.x - Int32(width + inset), y: corner.y + Int32(inset)),
                         size: SizeInt32(width: Int32(width), height: Int32(height)))
    }

    // MARK: Settings

    /// Ctrl+, (Arc's ⌘,): the Settings window, centred on this one when it opens.
    func openSettings(pane: DiaSettingsPane? = nil) {
        if Self.settingsWindow == nil {
            do {
                Self.settingsWindow = try SettingsWindow(store: store)
            } catch {
                print("The Settings window could not be made: \(error)")
                return
            }
        }
        Self.settingsWindow?.onNewProfile = { [weak self] in self?.showNewProfile(ticked: []) }
        Self.settingsWindow?.onImport = { [weak self] in self?.showImportDialog() }
        Self.settingsWindow?.onOpenURL = { [weak self] url in
            guard let self else { return }
            self.store.createTab(url: url, window: self.windowID)
            self.activate()
        }
        Self.settingsWindow?.onOpenProfilePage = { [weak self] url, profile in
            guard let self, !self.isIncognito else { return }
            let spaces = self.store.spaces(usingProfile: profile).map(\.id)
            guard let space = BrowserLanguages.space(focused: self.store.focusedSpaceID(window: self.windowID), onProfile: spaces)
            else { return }
            self.store.createTab(url: url, in: space, window: self.windowID)
            self.activate()
        }
        if let pane { Self.settingsWindow?.show(over: window, pane: pane) } else { Self.settingsWindow?.show(over: window) }
    }

    /// Arc's Help ▸ Essential Keyboard Shortcuts card; its View All is Settings ▸ Shortcuts.
    private func showEssentialShortcuts() {
        guard let window else { return }
        let card = essentialShortcutsCard ?? EssentialShortcutsCard()
        essentialShortcutsCard = card
        card.onViewAll = { [weak self] in self?.openSettings(pane: .shortcuts) }
        card.show(over: window)
    }

    // MARK: Developer Mode

    private func makeDeveloperBar() {
        developerBar.onAction = { [weak self] id in self?.perform(id) }
        developerBar.onKey = { [weak self] key in self?.handleShortcut(key) ?? false }
        developerBar.onEditEnded = { [weak self] in self?.focusContent() }
        // Arc's developer bar edits its full URL in place (ContentPanelTextField): what's typed
        // loads in the tab, or searches.
        developerBar.onCommit = { [weak self] typed in
            guard let self else { return }
            self.loadInSelectedTab(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : self.engine.searchURL(typed))
        }
    }

    /// Arc's per-site Developer Mode (View ▸ Developer): the bar over the page, the site's host
    /// and port under its tabs' titles, and a ring round the open one.
    private func toggleDeveloperMode() {
        guard let url = store.selectedTab(window: windowID)?.tab?.url, !url.isEmpty else { return }
        store.settings.toggleDeveloperMode(url: url)
    }

    /// The strip over the page (WindowTopBar): the developer bar over the open tab's page when its
    /// site is in Developer Mode (the Mac's ToolbarComposition kind `.developer`), else Arc's
    /// toolbar with View ▸ Show Toolbar, neither over a split; the pages move down under it.
    private func syncTopBar() {
        let tab = store.selectedTab(window: windowID)
        let url = tab?.tab?.url ?? ""
        let bar = WindowTopBar.resolve(showToolbar: store.settings.showToolbar, developerMode: !url.isEmpty && store.settings.isDeveloperMode(url: url),
                                       paneCount: paneIDs.count, hasURL: !url.isEmpty)
        topBar = bar
        let on = bar == .developer
        // An edit ends without loading when the bar goes or shows another tab (as on the Mac):
        // the keyboard goes back to the page.
        if developerBar.isEditing, !on || tab?.id != developerTabID {
            developerBar.resignEditing()
            focusContent()
        }
        developerTabID = on ? tab?.id : nil
        if on { developerBar.show(url: url, theme: store.focusedSpace(window: windowID).theme) }
        developerBar.root.visibility = on ? .visible : .collapsed
        pageToolbar.root.visibility = bar == .toolbar ? .visible : .collapsed
        if bar == .toolbar { syncToolbar() }
        // The toolbar carries ← → ↻ and the address, so the sidebar's header doesn't (Arc).
        let sidebarNav: Visibility = store.settings.showToolbar && paneIDs.count <= 1 ? .collapsed : .visible
        for part in sidebarNavigation { part.visibility = sidebarNav }
        syncHeaderLayout()
        let floats = ToolbarAutoHide.floats(enabled: store.settings.autoHideToolbar, toolbarShown: bar == .toolbar, panes: max(1, paneIDs.count),
                                            developerBar: false, devToolsOpen: false, pageFullscreen: false)
        if floats != toolbarFloats {
            toolbarFloats = floats
            toolbarTracker.reset()
            if floats { startToolbarPoll() } else { stopToolbarPoll() }
        }
        window.topBarFloats = floats
        window.topBarHeight = switch bar {
        case .developer: DeveloperBarView.height
        case .toolbar: floats && !toolbarTracker.shown ? 0 : ToolbarView.height
        case .none: 0
        }        // The focused pane's bar shows all its controls (a selection inside a split lands here).
        syncPaneBars()
    }

    private func startToolbarPoll() {
        guard toolbarPoll == nil, let timer = try? dispatcher.createTimer() else { return }
        timer.interval = TimeSpan(duration: 30 * 10_000)
        timer.isRepeating = true
        timer.tick.addHandler { [weak self] _, _ in self?.pollToolbar() }
        toolbarPoll = timer
        try? timer.start()
    }

    private func stopToolbarPoll() {
        try? toolbarPoll?.stop()
        toolbarPoll = nil
    }

    /// One pointer sample for the floating toolbar, in DIPs with y growing upward as CraCore's
    /// ToolbarAutoHide reads them: the card is the page area, the container the client area.
    private func pollToolbar() {
        guard toolbarFloats, !closing, let window, let host = HWND(bitPattern: hwnd) else { return }
        let scale = window.scale
        let size = window.appWindow.clientSize
        let frame = window.contentFrame
        var p = POINT()
        _ = GetCursorPos(&p)
        _ = ScreenToClient(host, &p)
        let height = Double(size.height) / scale
        let point = CGPoint(x: Double(p.x) / scale, y: height - Double(p.y) / scale)
        let card = CGRect(x: Double(frame.x) / scale, y: 0, width: Double(frame.width) / scale, height: height)
        let container = CGRect(x: 0, y: 0, width: Double(size.width) / scale, height: height)
        // Another app in front: the pointer is nowhere near this toolbar.
        let front = GetForegroundWindow().map { GetAncestor($0, UINT(GA_ROOTOWNER)) == host } ?? false
        let pointer: ToolbarAutoHide.Pointer = front && !IsIconic(host)
            ? ToolbarAutoHide.classify(point, card: card, container: container, barHeight: ToolbarView.height, shown: toolbarTracker.shown)
            : .away
        // A press (a drag or a menu pulled from the bar) or the Site Control Center under it keeps it out.
        let held = Self.isDown(0x01) || siteControlShown || commandBar.isOpen
        let was = toolbarTracker.shown
        toolbarTracker.sample(pointer, held: held, at: Date().timeIntervalSinceReferenceDate)
        guard toolbarTracker.shown != was else { return }
        window.topBarHeight = toolbarTracker.shown ? ToolbarView.height : 0
        placeLoadingBar()
    }

    /// Arc's sidebar header by width (SidebarHeaderLayout, #287): from 212 DIPs the toggle then ← → ↻
    /// as 32 DIP boxes 2 apart; under it ← → ••• as 28 DIP boxes with no gap and no toggle, both at
    /// the sidebar's right. With the toolbar shown only the toggle is left (28 under 212).
    private func syncHeaderLayout() {
        guard let row = headerRow, let b = headerButtons, let toggle = sidebarToggle else { return }
        let narrow = SidebarHeaderLayout.isNarrow(width: tabSidebarWidth)
        let toolbarHasNav = sidebarNavigation.last?.visibility == .collapsed
        let size = narrow ? 28.0 : 32.0
        row.spacing = narrow ? 0 : 2
        row.horizontalAlignment = toolbarHasNav ? .left : .right
        toggle.visibility = narrow && !toolbarHasNav ? .collapsed : .visible
        b.reload.visibility = narrow || toolbarHasNav ? .collapsed : .visible
        b.more.visibility = narrow && !toolbarHasNav ? .visible : .collapsed
        for button in [toggle, b.back, b.forward, b.reload, b.more] {
            button.width = size
            button.height = size
            button.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        }
    }

    /// The toolbar's buttons and colour for the open tab (its page's state, which isn't observed:
    /// the page's own callbacks call this too).
    private func syncToolbar() {
        syncPaneBars()
        guard topBar == .toolbar else { return }
        let item = store.selectedTab(window: windowID)
        var state = ToolbarView.State()
        if let item, let t = item.tab, !item.isEmptyTab {
            state.kind = .normal
            state.url = t.url
            state.easelTitle = item.displayTitle
            state.themeColor = ToolbarColor.hex(reported: nil, remembered: t.themeColor)
        }
        if let page = shownPage {
            state.canGoBack = canGoBackInSaved(page)
                || (tabID(of: page).map { store.backStep($0, canGoBack: page.canGoBack) != .none } ?? page.canGoBack)
            state.canGoForward = page.canGoForward || canGoForwardInSaved(page)
            state.isLoading = page.isLoading
        }
        state.sidebarVisible = sidebarDocked
        state.sidebarSide = store.settings.sidebarSide
        state.showFullURL = store.settings.toolbarShowsFullURL
        state.autoHide = store.settings.autoHideToolbar
        state.pins = toolbarPins(scale: window?.scale ?? 1)
        pageToolbar.show(state)
    }

    private func makeToolbar() {
        pageToolbar.menus = (backMenu, forwardMenu, reloadMenu)
        pageToolbar.onKey = { [weak self] key in self?.handleShortcut(key) ?? false }
        pageToolbar.onAction = { [weak self] id in
            guard let self else { return }
            switch id {
            case "siteControls": self.toggleSiteControlCenter()
            case let id where id.hasPrefix(ToolbarView.pinAction):
                let ext = String(id.dropFirst(ToolbarView.pinAction.count))
                self.runExtension(ext, anchor: self.pageToolbar.pinButtons[ext].map { ($0, true) })
            case "toggleFullURL": self.store.settings.toolbarShowsFullURL.toggle()
            case "toggleAutoHideToolbar": self.store.settings.autoHideToolbar.toggle()
            case "stop": self.shownPage?.stopLoading()
            default: _ = self.perform(id)
            }
        }
    }

    // MARK: Keys

    /// Shortcuts Cra keeps from the page: Windows' table with the user's own keys (Settings ▸
    /// Shortcuts, keybindings.json).
    /// A Ctrl+Alt chord that types a character on the keyboard layout (AltGr+N is ń on Polish
    /// keyboards) is left to type.
    private func handleShortcut(_ key: KeyPress) -> Bool {
        guard !WinKeyboard.typesCharacter(key),
              let chord = KeyChord(windowsVirtualKey: key.keyCode, control: key.control, shift: key.shift, alt: key.alt),
              let action = WinKeyBindings.shared.action(matching: chord) else { return false }
        return perform(action.id)
    }

    private func reload(ignoringCache: Bool) {
        if ignoringCache { shownPage?.reloadIgnoringCache() } else { shownPage?.reload() }
    }

    // MARK: Split view

    /// Arc's "Add Split View" (Ctrl+Shift+=): an empty pane next to the focused one, the command
    /// bar asking what it shows (MainWindowController.addSplitPane). Arc stops at four panes.
    private func addSplitPane() {
        guard let current = store.selectedTabID(window: windowID) else { return beginNewTab() }
        guard store.paneTabIDs(for: current).count < SplitPaneLayout.Constants.maximumPanes else { return }
        guard store.addEmptyPane(nextTo: current) != nil else { return }
        // syncPages sees the empty pane selected and opens the bar.
    }

    /// Arc's "Close this Split Pane" (Ctrl+Shift+-): the pane's tab closes like any tab and the
    /// split keeps the other panes. A pinned split's pane leaves it (closing it would only
    /// unload the whole split).
    func closeSplitPane(_ id: UUID) {
        guard store.splitContaining(id) != nil else { return closeTab(id) }
        if store.item(id)?.isEmptyTab == true || store.isPinned(id) {
            store.archiveTab(id, reason: .manual)
        } else {
            closeTab(id)
        }
    }

    /// Arc's "Separate Page from Split View": the pane becomes a normal tab again.
    func separatePane(_ id: UUID) {
        guard store.splitContaining(id) != nil else { return }
        store.separateFromSplit(id)
        store.selectTab(id, window: windowID)
    }

    /// Arc's Reveal Tab in Sidebar: the open tab's folders open, and a collapsed pinned section
    /// shows it again; the Library gives the sidebar back.
    private func revealSelectedTab() {
        guard let id = store.selectedTabID(window: windowID) else { return }
        store.revealInSidebar(store.splitContaining(id)?.id ?? id)
        closeLibrary()
    }

    /// Arc's View ▸ Expand Current Split: the pane takes the window and the others keep the
    /// minimum width, stored as the split's width factors like a divider drag
    /// (SplitPaneLayout.expanding). A divider drag brings the panes back.
    private func expandSplitPane(_ id: UUID) {
        guard let split = store.splitContaining(id) else { return }
        let factors = SplitPaneLayout.expanding(id, in: store.paneTabIDs(for: id))
        store.setSplitWidthFactors(split.id, factors.mapValues { Double($0) })
    }

    /// Arc's "Open in Split View" on a sidebar tab: it joins the open tab in a split (a new one
    /// in its place, or the open split), as the Mac's openTabInSplit does.
    func openInSplitView(_ id: UUID) {
        guard let current = store.selectedTabID(window: windowID), current != id, store.item(current)?.isEmptyTab == false else { return }
        if store.paneTabIDs(for: current).contains(id) {
            store.selectTab(id, window: windowID)
            return
        }
        guard store.canAddPane(to: current) else {
            showToast("Cannot Add New Pane")
            return
        }
        store.joinSplit(id, with: current, window: windowID)
    }

    /// Switch to Next / Previous Split View.
    private func cycleSplitPane(_ delta: Int) {
        guard let current = store.selectedTabID(window: windowID),
              let next = SplitPaneLayout.pane(delta, from: current, in: store.paneTabIDs(for: current)) else { return }
        store.selectTab(next, window: windowID)
    }

    /// Lays the panes out in the page area with CraCore's SplitPaneLayout (in DIPs, y down) and
    /// moves their pages there.
    private func layoutPanes() {
        guard let window, !closing else { return }
        let area = window.contentFrame, scale = window.scale
        let split = paneIDs.first.flatMap { store.splitContaining($0) }
        paneOrientation = split?.split?.orientation ?? .horizontal
        let factors = paneDrag?.factors ?? SplitPaneLayout.normalizedFactors(ids: paneIDs, stored: split?.split?.widthFactors ?? [:])
        let result = paneLayout(factors: factors).compute()
        paneLayoutResult = result
        func pixels(_ r: CGRect) -> PixelRect {
            func px(_ v: CGFloat) -> Int32 { Int32((Double(v) * scale).rounded()) }
            let x0 = px(r.minX), x1 = px(r.maxX), y0 = px(r.minY), y1 = px(r.maxY)
            return PixelRect(x: area.x + x0, y: area.y + y0, width: x1 - x0, height: y1 - y0)
        }
        let cards = result.frames.mapValues(pixels)
        // Each pane of a split has its bar over its page (SplitPaneOptionsMenu.barsShown).
        let bar = SplitPaneOptionsMenu.barsShown(panes: paneIDs.count, fullscreen: false) ? Int32((ToolbarView.height * scale).rounded()) : 0
        paneBarFrames = bar > 0 ? cards.mapValues { PixelRect(x: $0.x, y: $0.y, width: $0.width, height: min(bar, $0.height)) } : [:]
        paneFrames = bar > 0 ? cards.mapValues { c in
            let top = min(bar, c.height)
            return PixelRect(x: c.x, y: c.y + top, width: c.width, height: c.height - top)
        } : cards
        paneGaps = result.gaps.map(pixels)
        for (id, frame) in paneFrames { pages[id]?.frame = frame }
        placePaneBars()
        window.pill = paneDrag.flatMap { paneGaps.indices.contains($0.divider) ? pill(in: paneGaps[$0.divider]) : nil }
        placeFindBar()
        if slowResponseToastTab != nil { toast?.ownerMoved() }
    }

    /// Shows a bar over each pane of a split (none over a lone page, whose bar is the window's).
    private func placePaneBars() {
        guard let window else { return }
        guard !paneBarFrames.isEmpty else {
            hoveredPaneBar = nil
            window.setPaneBars([])
            return
        }
        while paneBars.count < paneIDs.count { paneBars.append(makePaneBar(index: paneBars.count)) }
        let none = PixelRect(x: 0, y: 0, width: 0, height: 0)
        window.setPaneBars(paneIDs.enumerated().map { i, id in (paneBars[i].root, paneBarFrames[id] ?? none) })
        syncPaneBars()
    }

    private func makePaneBar(index: Int) -> ToolbarView {
        let bar = ToolbarView()
        bar.onKey = { [weak self] key in self?.handleShortcut(key) ?? false }
        bar.onHover = { [weak self] over in
            guard let self else { return }
            if over { self.hoveredPaneBar = index } else if self.hoveredPaneBar == index { self.hoveredPaneBar = nil }
            self.syncPaneBars()
        }
        bar.onAction = { [weak self] action in self?.paneBarAction(action, index: index) }
        return bar
    }

    /// Each pane's bar for its own tab: the focused one carries all its controls, the others Arc's
    /// essentials until the pointer is over them (ToolbarComposition with `inSplit`).
    private func syncPaneBars() {
        guard !paneBarFrames.isEmpty else { return }
        let selected = store.selectedTabID(window: windowID)
        for (i, id) in paneIDs.enumerated() where i < paneBars.count {
            var state = ToolbarView.State()
            state.kind = .emptyPane
            if let item = store.item(id), let t = item.tab, !item.isEmptyTab {
                state.kind = .normal
                state.url = t.url
                state.easelTitle = item.displayTitle
                state.themeColor = ToolbarColor.hex(reported: nil, remembered: t.themeColor)
            }
            if let page = pages[id] {
                state.canGoBack = canGoBackInSaved(page) || store.backStep(id, canGoBack: page.canGoBack) != .none
                state.canGoForward = page.canGoForward || canGoForwardInSaved(page)
                state.isLoading = page.isLoading
            }
            state.sidebarVisible = sidebarDocked
            state.sidebarSide = store.settings.sidebarSide
            state.showFullURL = store.settings.toolbarShowsFullURL
            state.inSplit = true
            state.focusedPane = selected == id
            state.hovered = hoveredPaneBar == i
            paneBars[i].show(state)
        }
    }

    /// A click on a pane's bar acts on that pane: it takes the focus first, as Arc's bar does.
    private func paneBarAction(_ action: String, index: Int) {
        guard paneIDs.indices.contains(index) else { return }
        let id = paneIDs[index]
        if action == "closeSplitPane" { return closeSplitPane(id) }
        if store.selectedTabID(window: windowID) != id {
            store.selectTab(id, window: windowID)
            refresh()
        }
        switch action {
        case "splitOptions": showSplitOptions(for: id, from: paneBars[index].splitOptions)
        case "siteControls": toggleSiteControlCenter()
        case "toggleFullURL": store.settings.toolbarShowsFullURL.toggle()
        case "toggleAutoHideToolbar": store.settings.autoHideToolbar.toggle()
        case "stop": pages[id]?.stopLoading()
        default: _ = perform(action)
        }
    }

    /// Arc's Split View Options (SplitPaneOptionsMenu), for the pane whose bar it hangs from.
    private func showSplitOptions(for id: UUID, from anchor: Button?) {
        guard let anchor else { return }
        let menu = MenuFlyout()
        for entry in SplitPaneOptionsMenu.entries {
            guard let entry else {
                menu.items.append(MenuFlyoutSeparator())
                continue
            }
            menu.items.append(UI.menuItem(entry.title, action: entry.action) { [weak self] in
                guard let self else { return }
                switch entry.action {
                case "separateFromSplit": self.store.separateFromSplit(id)
                case "closeSplitPane": self.closeSplitPane(id)
                default: _ = self.perform(entry.action)
                }
            })
        }
        splitOptionsMenu = menu
        try? menu.showAt(anchor)
    }

    private func paneLayout(factors: [UUID: CGFloat]) -> SplitPaneLayout {
        let area = window.contentFrame, scale = window.scale
        let panes = paneIDs.map { SplitPaneLayout.Pane(id: $0, factor: factors[$0] ?? 1 / CGFloat(max(1, paneIDs.count))) }
        return SplitPaneLayout(panes: panes, orientation: paneOrientation,
                               containerSize: CGSize(width: Double(area.width) / scale, height: Double(area.height) / scale),
                               backingScaleFactor: CGFloat(scale), flipped: true)
    }

    /// The divider's pill while it is dragged (SplitDraggerHandleView.Style): 4 × 36 DIPs, centred.
    private func pill(in gap: PixelRect) -> PixelRect {
        let thick = Int32((4 * window.scale).rounded()), long = Int32((36 * window.scale).rounded())
        return paneOrientation == .horizontal
            ? PixelRect(x: gap.x + (gap.width - thick) / 2, y: gap.y + (gap.height - long) / 2, width: thick, height: long)
            : PixelRect(x: gap.x + (gap.width - long) / 2, y: gap.y + (gap.height - thick) / 2, width: long, height: thick)
    }

    /// The divider under a client point, in pixels, with Arc's hit outset.
    private func divider(x: Int32, y: Int32) -> Int? {
        let scale = window.scale, area = window.contentFrame
        return paneLayoutResult.divider(at: CGPoint(x: Double(x - area.x) / scale, y: Double(y - area.y) / scale))
    }

    private func paneCursor(x: Int32, y: Int32) -> HostCursor? {
        if paneDrag != nil || divider(x: x, y: y) != nil {
            return paneOrientation == .horizontal ? .resizeLeftRight : .resizeUpDown
        }
        return nil
    }

    /// Presses on the page area that no page covers: a divider drags (a double-click makes the
    /// panes equal again), an empty pane asks for its address.
    private func handlePaneMouse(_ event: HostMouseEvent) {
        switch event {
        case .down(let x, let y, let clicks):
            if let index = divider(x: x, y: y), let split = paneIDs.first.flatMap({ store.splitContaining($0) }) {
                if clicks == 2 {
                    paneDrag = nil
                    store.setSplitWidthFactors(split.id, [:])
                    return
                }
                let factors = SplitPaneLayout.normalizedFactors(ids: paneIDs, stored: split.split?.widthFactors ?? [:])
                paneDrag = (divider: index, x: x, y: y, start: factors, factors: factors)
                layoutPanes()
            } else if let id = paneIDs.first(where: { paneFrames[$0].map { Self.contains($0, x: x, y: y) } == true }), pages[id] == nil {
                if store.selectedTabID(window: windowID) == id { openCommandBar(.editURL) } else { store.selectTab(id, window: windowID) }
            }
        case .move(let x, let y):
            guard let drag = paneDrag else { return }
            let delta = paneOrientation == .horizontal ? Double(x - drag.x) : Double(y - drag.y)
            paneDrag?.factors = paneLayout(factors: drag.start).dragging(dividerAfter: drag.divider, by: CGFloat(delta / window.scale)).factors
            layoutPanes()
        case .up, .cancelled:
            guard let drag = paneDrag else { return }
            paneDrag = nil
            if let split = paneIDs.first.flatMap({ store.splitContaining($0) }) {
                store.setSplitWidthFactors(split.id, drag.factors.mapValues { Double($0) })
            }
            layoutPanes()
        }
    }

    private static func contains(_ r: PixelRect, x: Int32, y: Int32) -> Bool {
        x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height
    }

    /// The page area's own colour (between panes, in an empty pane) is the sidebar's.
    /// The sidebar shows its slice of Arc's window gradient (45° from the window's top left, #669),
    /// so it follows the window's size and the column's place in it.
    private func paintSidebarGradient() {
        let scale = window.scale, size = window.appWindow.clientSize, origin = window.columnOrigin
        let key = [size.width, size.height, origin.x, origin.y].map(Double.init) + [scale]
        // Mid-switch, the colours on their way from the last space's to this one's (slideTick).
        let colors = slide.map { SpaceSwitchSlide.colors($0.from, sidebar.palette.colors, blend: $0.blend) } ?? sidebar.palette.colors
        guard key != gradientKey || colors != gradientColors else { return }
        gradientKey = key
        gradientColors = colors
        sidebarPanel.background = sidebar.palette.windowFill(width: Double(size.width) / scale, height: Double(size.height) / scale,
                                                             originX: Double(origin.x) / scale, originY: Double(origin.y) / scale,
                                                             colors: colors)
    }

    /// A switch to another space slides its part of the sidebar in from its side of the dock on Arc's
    /// spring while the gradient cross-fades (SpaceSwitchSlide, the Mac's pager). Called after each
    /// drawing with the space it drew.
    private func slideIfSwitched(to space: UUID) {
        defer { slidSpace = space }
        guard let last = slidSpace, last != space, let from = lastDrawnColors else { return }
        let order = store.pagedSpaces(window: windowID).map(\.id)
        let direction = SpaceSwitchSlide.direction(from: order.firstIndex(of: last), to: order.firstIndex(of: space))
        guard direction != 0, !WinAppearance.reduceMotion else { return }
        // A switch mid-slide starts from the colours shown now.
        let shown = slide.map { SpaceSwitchSlide.colors($0.from, from, blend: $0.blend) } ?? from
        slide = (from: shown, direction: Double(direction), started: ProcessInfo.processInfo.systemUptime, blend: 0)
        sidebar.slideSpace(offset: Double(direction))
        paintSidebarGradient()
        if slideTimer == nil, let queue = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil {
            slideTimer = try? queue.createTimer()
            slideTimer?.interval = TimeSpan(duration: 160_000)  // 16 ms
            slideTimer?.isRepeating = true
            slideTimer?.tick.addHandler { [weak self] _, _ in self?.slideTick() }
        }
        try? slideTimer?.start()
    }

    private func slideTick() {
        guard var s = slide, !closing else {
            try? slideTimer?.stop()
            return
        }
        let width = sidebarPanel.actualWidth
        let f = SpaceSwitchSlide.frame(at: ProcessInfo.processInfo.systemUptime - s.started, width: width)
        if f.done {
            slide = nil
            try? slideTimer?.stop()
            sidebar.slideSpace(offset: 0)
        } else {
            s.blend = f.blend
            slide = s
            sidebar.slideSpace(offset: f.offset * s.direction)
        }
        paintSidebarGradient()
    }

    private func applyPaneColors(_ theme: SpaceTheme) {
        // The sidebar's top colour, as its palette draws it (SidebarSurface over SidebarMaterialFill's grey).
        let c = sidebar.palette.top
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        let fill = HostColor(r: byte(c.r), g: byte(c.g), b: byte(c.b))
        window.background = fill
        window.pillColor = fill.blended(with: sidebar.palette.isDark ? HostColor(r: 255, g: 255, b: 255) : HostColor(r: 0, g: 0, b: 0), alpha: 0.45)
    }

    // MARK: Permissions

    private func makePermissionPrompt() {
        permissionPrompt.onAnswer = { [weak self] allowed in self?.answerPermission(allowed) }
        do {
            permissionWindow = try FloatingWindow(owner: window, content: permissionPrompt.root)
            // Alt+F4 on the prompt blocks, as closing the Mac's sheet would.
            permissionWindow?.onClose = { [weak self] in self?.answerPermission(false) }
        } catch {
            print("The permission prompt's window could not be made: \(error)")
        }
    }

    /// The tabs on screen changed, or a card went: a card whose page went behind steps aside
    /// (unanswered, first in line again) and the oldest request whose page is on screen asks.
    /// A page that closed has no say any more. True when a card is up.
    @discardableResult private func askNextPermission() -> Bool {
        let dead = permissions.remove { $0.page.page == nil || $0.page.page?.isClosed == true }
        let change = permissions.tabsChanged { $0.page.page?.isVisible == true }
        if dead.wasAsking || change.aside != nil { permissionWindow?.hide() }
        if change.next != nil { showAskingPermission() }
        return permissions.asking != nil
    }

    /// The asking request's question over the page.
    private func showAskingPermission() {
        guard let request = permissions.asking, let permissionWindow, !closing else {
            permissionWindow?.hide()
            return
        }
        permissionHeight = permissionPrompt.show(origin: request.origin, kinds: UInt(request.kinds.rawValue),
                                                 dark: store.focusedSpace(window: windowID).theme.isDark)
        placePermissionPrompt()
        permissionWindow.show { [weak self] in self?.permissionPrompt.focus() }
    }

    private func answerPermission(_ allowed: Bool) {
        guard let request = permissions.finish() else { return }
        request.answer(allowed)
        permissionWindow?.hide()
        if !askNextPermission() {
            if let window = HWND(bitPattern: hwnd) { _ = SetForegroundWindow(window) }
            focusContent()
        }
    }

    /// Centred over the page area, 12 DIPs below its top (where the Mac's sheet drops from).
    private func placePermissionPrompt() {
        guard let permissionWindow, permissions.asking != nil, let window, let host = HWND(bitPattern: hwnd) else { return }
        let scale = window.scale, area = window.contentFrame
        let width = Int32((PermissionPromptView.width * scale).rounded()), height = Int32((permissionHeight * scale).rounded())
        var corner = POINT(x: area.x + (area.width - width) / 2, y: area.y + Int32((12 * scale).rounded()))
        _ = ClientToScreen(host, &corner)
        permissionWindow.place(origin: PointInt32(x: corner.x, y: corner.y), size: SizeInt32(width: width, height: height))
    }

    // MARK: Profiles

    private func makeProfileDialog() {
        profileDialog.onCreate = { [weak self] name, spaces in
            self?.store.createProfile(name: name, forSpaces: spaces)
            self?.hideProfileDialog()
        }
        profileDialog.onChange = { [weak self] space, profile in
            self?.store.setProfile(profile, forSpace: space)
            self?.hideProfileDialog()
        }
        profileDialog.onCancel = { [weak self] in self?.hideProfileDialog() }
        profileDialog.onResize = { [weak self] height in
            self?.profileDialogHeight = height
            self?.placeProfileDialog()
        }
        do {
            profileWindow = try FloatingWindow(owner: window, content: profileDialog.root)
            // Alt+F4 on the dialog cancels it.
            profileWindow?.onClose = { [weak self] in self?.hideProfileDialog() }
        } catch {
            print("The profile dialog's window could not be made: \(error)")
        }
    }

    /// Create a new Profile (Set Profile ▸ New Profile…, Settings ▸ Profiles ▸ Create Profile…),
    /// with `ticked` spaces chosen on its second step.
    func showNewProfile(ticked: Set<UUID>) {
        guard !closing else { return }
        profileDialogHeight = profileDialog.showNew(spaces: store.profileSpaces, ticked: ticked)
        presentProfileDialog()
    }

    /// Spaces ▸ Change Profile for the space.
    func showChangeProfile(forSpace id: UUID) {
        guard !closing, let space = store.space(id), !store.isIncognito(space: id) else { return }
        profileDialogHeight = profileDialog.showChange(space: space, profiles: store.profiles, defaultName: store.profileName(nil), spaces: store.profileSpaces)
        presentProfileDialog()
    }

    /// After the event that asked for it (a menu item, a key), as the command bar opens.
    private func presentProfileDialog() {
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, let profileWindow = self.profileWindow, !self.closing else { return }
            self.placeProfileDialog()
            profileWindow.show { [weak self] in self?.profileDialog.focus() }
        }
    }

    private func hideProfileDialog() {
        guard profileWindow?.isVisible == true else { return }
        profileWindow?.hide()
        if let window = HWND(bitPattern: hwnd) { _ = SetForegroundWindow(window) }
        focusContent()
    }

    /// Centred on the window, as Arc's card is.
    private func placeProfileDialog() {
        guard let profileWindow, let window else { return }
        let scale = window.scale
        let position = window.appWindow.position, size = window.appWindow.size
        let width = (ProfileDialogView.width * scale).rounded(), height = (profileDialogHeight * scale).rounded()
        let left = Double(position.x) + (Double(size.width) - width) / 2
        let top = Double(position.y) + max(0, (Double(size.height) - height) / 2)
        profileWindow.place(origin: PointInt32(x: Int32(left.rounded()), y: Int32(top.rounded())),
                            size: SizeInt32(width: Int32(width), height: Int32(height)))
    }

    // MARK: Quit

    /// Shows `dialog` as Arc's dialog sheet centred on the window; `answer` gets the button
    /// pressed, or stay for Escape, Alt+F4 on the card and the window going first.
    func askToQuit(_ dialog: QuitDialog, answer: @escaping (QuitDialog.Answer) -> Void) {
        guard !closing, quitSheet == nil else { return answer(.stay) }
        let sheet = AppDialog(title: dialog.title, message: dialog.message ?? "", actions: dialog.actions)
        quitSheet = sheet
        print("Cra: quit asks: \(dialog.title)")
        // After the key or click that asked, as the profile dialog shows.
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { self?.quitSheet = nil; return answer(.stay) }
            sheet.present(over: self.window) { [weak self] picked in
                guard let self else { return answer(dialog.answer(picked: picked)) }
                self.quitSheet = nil
                let picked = dialog.answer(picked: picked)
                if let window = HWND(bitPattern: self.hwnd) { _ = SetForegroundWindow(window) }
                if picked == .stay { self.focusContent() }
                answer(picked)
            }
        }
    }

    // MARK: Import

    private func makeImportDialog() {
        importDialog.onImport = { [weak self] source, credentials, extensions in
            self?.runImport(source, credentials: credentials, extensions: extensions)
        }
        importDialog.onCancel = { [weak self] in self?.hideImportDialog() }
        importDialog.extensionsOf = { [weak self] source in self?.importableExtensions(source) ?? ([], []) }
        importDialog.onHeightChange = { [weak self] height in
            self?.importDialogHeight = height
            self?.placeImportDialog()
        }
        do {
            importWindow = try FloatingWindow(owner: window, content: importDialog.root)
            importWindow?.onClose = { [weak self] in self?.hideImportDialog() }
        } catch {
            print("The import dialog's window could not be made: \(error)")
        }
    }

    /// Import from Another Browser…: the browsers with data on this PC.
    func showImportDialog() {
        guard !closing else { return }
        let folders = WindowsImportSource.Folders(environment: ProcessInfo.processInfo.environment)
        let sources = folders.map { f in WindowsImportSource.available(in: f).map { (source: $0, profiles: $0.profiles(in: f)) } } ?? []
        importDialogHeight = importDialog.show(sources)
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, let importWindow = self.importWindow, !self.closing else { return }
            self.placeImportDialog()
            importWindow.show { [weak self] in self?.importDialog.focus() }
        }
    }

    /// Adds the browser's plan to the sidebar, shows its first space and says what came over.
    /// With `credentials`, its passwords and sign-ins are staged for the next launch, and
    /// `extensions` are copied into Cra's folder. The card stays up with Done to say what came
    /// over, as the Mac's progress step does. With nothing but the sidebar it used to close and
    /// leave a toast, which went unseen (PR #43's PC test saw no result at all).
    private func runImport(_ source: WindowsImportSource, credentials: Bool, extensions: [ExtensionImport.Candidate] = []) {
        switch importData(source, credentials: credentials, extensions: extensions) {
        case .failed(let error):
            hideImportDialog()
            showToast(error)
        case .done(let summary, let words):
            importDialogHeight = importDialog.showResult(title: summary, lines: words.map { [$0] } ?? [])
            placeImportDialog()
            importDialog.focus()
        }
    }

    /// The import itself, for Import from Another Browser and the onboarding: the plan into the
    /// sidebar (its first space shown), with `credentials` the passwords and sign-ins staged, and
    /// `extensions` copied into Cra's Extensions folder (as Extensions/<id>, loaded from the next start).
    private func importData(_ source: WindowsImportSource, credentials: Bool,
                            extensions: [ExtensionImport.Candidate] = []) -> OnboardingView.ImportOutcome {
        guard let folders = WindowsImportSource.Folders(environment: ProcessInfo.processInfo.environment) else {
            return .failed("Could not import from \(source.name)")
        }
        let summary: String
        var profiles = ImportProfileMap()
        do {
            let plan = try source.plan(in: folders) { file, query in SQLiteSnapshot(copying: file)?.rows(query) ?? [] }
            let result = store.apply(plan, includeArchive: true, includeSettings: source.kind == .arc, favicons: Favicons.folder)
            if let first = result.spaceIDs.first { store.focusSpace(first, window: windowID) }
            summary = result.summary(from: source.name)
            profiles = result.profiles
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? "Could not import from \(source.name)")
        }
        var report = CredentialImportReport()
        if credentials, let userData = source.userData(in: folders) {
            let read = CredentialImport.read(userData: userData, profiles: source.profiles(in: folders))
            report = read.report
            if !CredentialImport.stage(read.credentials, profiles: profiles) { report.failed = true }
        }
        var copied = 0, failed: [String] = []
        for e in extensions {
            do {
                try ExtensionImport.copy(e.folder, id: e.id, into: WinPaths.extensions)
                copied += 1
            } catch {
                print("import: \(e.id) couldn't be copied: \(error)")
                failed.append(e.name)
            }
        }
        if copied > 0 { ExtensionList.shared.needsRestart = true }
        // The source browser's toolbar pins, after the extensions are in (as on the Mac).
        if let userData = source.userData(in: folders) { ExtensionPins.shared.seedImport(userData: userData, map: profiles) }
        let details = [report.summary(from: source.name), ExtensionImport.summary(imported: copied, failed: failed)].compactMap { $0 }
        return .done(summary: summary, credentials: details.isEmpty ? nil : details.joined(separator: " "))
    }

    /// The browser's extensions, and the IDs Cra has already, for the import's extensions page.
    private func importableExtensions(_ source: WindowsImportSource) -> (candidates: [ExtensionImport.Candidate], installed: Set<String>) {
        guard let folders = WindowsImportSource.Folders(environment: ProcessInfo.processInfo.environment),
              let userData = source.userData(in: folders) else { return ([], []) }
        return (ExtensionImport.candidates(inUserData: userData), installedExtensionIDs())
    }

    /// Every extension ID Cra has: installed in any of its profiles (turned off too), or waiting in
    /// its Extensions folder for the next start.
    private func installedExtensionIDs() -> Set<String> {
        let paths: [String?] = [nil] + store.profiles.map { store.profilePath(profile: $0.id) }
        var ids = Set(ExtensionFolders.loadable(in: WinPaths.extensions).map(\.lastPathComponent))
        for path in paths {
            for e in ExtensionList.shared.entries(profilePath: path, chromiumCache: store.chromiumCache) { ids.insert(e.id) }
        }
        return ids
    }

    // MARK: Onboarding

    /// The first-run onboarding, on a card over this window (Onboarding.isNeeded decides).
    func showOnboarding() {
        guard !closing, !isIncognito, onboardingWindow == nil else { return }
        let view = OnboardingView()
        let folders = WindowsImportSource.Folders(environment: ProcessInfo.processInfo.environment)
        let sources = folders.map { f in WindowsImportSource.available(in: f).map { OnboardingView.Source(source: $0, profiles: $0.profiles(in: f)) } } ?? []
        view.extensionsOf = { [weak self] source in self?.importableExtensions(source) ?? ([], []) }
        view.importData = { [weak self] source, credentials, extensions in
            guard let self else { return .failed("") }
            let outcome = self.importData(source, credentials: credentials, extensions: extensions)
            // Showing the imported space brings this window forward; the card takes the
            // keyboard back so Return still presses Continue (PR #38's PC test).
            _ = try? self.dispatcher.tryEnqueue { [weak self] in
                guard let self, let window = self.onboardingWindow, window.isVisible else { return }
                window.show { [weak self] in self?.onboarding?.focus() }
            }
            return outcome
        }
        view.pinCandidates = { [weak self] source in
            guard let self else { return (Onboarding.presetPins, []) }
            return OnboardingSites.candidates(source: source, sources: sources, existingHosts: self.favoriteHosts)
        }
        view.pin = { [weak self] picked in
            guard let self, !picked.isEmpty else { return }
            var plan = ImportPlan(source: "Onboarding")
            plan.favorites = picked.map { ImportedItem(customTitle: $0.name, pageTitle: $0.name, url: $0.url) }
            self.store.apply(plan, includeArchive: false, includeSettings: false, favicons: nil)
        }
        view.chooseTheme = { [weak self] i in
            guard let self, SpaceTheme.presets.indices.contains(i) else { return }
            var space = self.store.focusedSpace(window: self.windowID)
            space.theme = SpaceTheme.presets[i]
            self.store.updateSpace(space)
        }
        view.blocksAds = { [weak self] in self?.store.settings.blockAdsAndTrackers ?? true }
        view.setBlocksAds = { [weak self] on in self?.store.settings.blockAdsAndTrackers = on }
        view.addressBar = { [weak self] in self?.store.settings.addressBarPlacement ?? .sidebar }
        view.setAddressBar = { [weak self] placement in self?.store.settings.addressBarPlacement = placement }
        view.applySystemOptions = { makeDefault, launch in
            if makeDefault && !DefaultBrowser.isDefault && !DefaultBrowser.makeDefault() {
                return "Cra couldn’t register itself with Windows as a browser."
            }
            if launch != LaunchAtLogin.isEnabled, let error = LaunchAtLogin.set(launch) { return error }
            return nil
        }
        view.finish = { [weak self] in self?.finishOnboarding() }
        do {
            let window = try FloatingWindow(owner: self.window, content: view.root)
            // Alt+F4: put away for now; the next launch shows it again.
            window.onClose = { [weak self] in self?.hideOnboarding() }
            onboardingWindow = window
        } catch {
            print("The onboarding's window could not be made: \(error)")
            return
        }
        onboarding = view
        let flow = Onboarding.windowsFlow(isDefaultBrowser: DefaultBrowser.isDefault, favoriteCount: favoriteHosts.count)
        view.start(flow: flow, sources: sources, launchesAtLogin: LaunchAtLogin.isEnabled)
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, let window = self.onboardingWindow, !self.closing else { return }
            self.placeOnboarding()
            window.show { [weak self] in self?.onboarding?.focus() }
        }
    }

    /// The hosts of this window's space's favorites.
    private var favoriteHosts: Set<String> {
        let space = store.focusedSpace(window: windowID)
        return Set(store.tabs(under: space.favoritesContainerID).compactMap { $0.tab.flatMap { FaviconKey.key(for: $0.url) } })
    }

    /// The onboarding ended: it counts as seen from now on.
    private func finishOnboarding() {
        store.settings.hasSeenImportPrompt = true
        hideOnboarding()
    }

    /// The card's window stays made (hidden) for the rest of the run, as the import card's does.
    private func hideOnboarding() {
        onboardingWindow?.hide()
        if let window = HWND(bitPattern: hwnd) { _ = SetForegroundWindow(window) }
        focusContent()
    }

    /// Centred on the window, as the import card is.
    private func placeOnboarding() {
        guard let onboardingWindow, let window else { return }
        let scale = window.scale
        let position = window.appWindow.position, size = window.appWindow.size
        let width = (OnboardingView.width * scale).rounded(), height = (OnboardingView.height * scale).rounded()
        let left = Double(position.x) + (Double(size.width) - width) / 2
        let top = Double(position.y) + max(0, (Double(size.height) - height) / 2)
        onboardingWindow.place(origin: PointInt32(x: Int32(left.rounded()), y: Int32(top.rounded())),
                               size: SizeInt32(width: Int32(width), height: Int32(height)))
    }

    private func hideImportDialog() {
        guard importWindow?.isVisible == true else { return }
        importWindow?.hide()
        if let window = HWND(bitPattern: hwnd) { _ = SetForegroundWindow(window) }
        focusContent()
    }

    /// Centred on the window, as the profile dialogs are.
    private func placeImportDialog() {
        guard let importWindow, let window else { return }
        let scale = window.scale
        let position = window.appWindow.position, size = window.appWindow.size
        let width = (ImportDialogView.width * scale).rounded(), height = (importDialogHeight * scale).rounded()
        let left = Double(position.x) + (Double(size.width) - width) / 2
        let top = Double(position.y) + max(0, (Double(size.height) - height) / 2)
        importWindow.place(origin: PointInt32(x: Int32(left.rounded()), y: Int32(top.rounded())),
                           size: SizeInt32(width: Int32(width), height: Int32(height)))
    }

    // MARK: Site Control Center

    private func makeSiteControlCenter() {
        siteControl.ownerWindow = { [weak self] in self?.siteControlWindow?.hwnd ?? 0 }
        siteControl.onEscape = { [weak self] in self?.hideSiteControlCenter(refocus: true) }
        // An install or a switch in chrome://extensions while it shows: its tiles follow. So
        // does a pin or an unpin, here or in another window, and the toolbar's buttons with it.
        ExtensionList.shared.onChange.append { [weak self] in
            self?.syncToolbar()
            self?.syncPillPins()
            guard let self, self.siteControlShown else { return }
            self.showSiteControlCenter()
        }
        ExtensionPins.shared.onChange.append { [weak self] in
            self?.syncToolbar()
            self?.syncPillPins()
            guard let self, self.siteControlShown else { return }
            self.showSiteControlCenter()
        }
        do {
            siteControlWindow = try FloatingWindow(owner: window, content: siteControl.root)
            // A click anywhere else closes it, as Arc's transient popover.
            siteControlWindow?.onDeactivate = { [weak self] in
                self?.siteControlClosed = Date()
                self?.hideSiteControlCenter()
            }
        } catch {
            print("The Site Control Center's window could not be made: \(error)")
        }
    }

    private var siteControlShown: Bool { siteControlWindow?.isVisible == true }

    /// The sliders: the Site Control Center for the page on screen, or closes it.
    private func toggleSiteControlCenter() {
        if siteControlShown { return hideSiteControlCenter(refocus: true) }
        // The press that just closed it from outside.
        guard Date().timeIntervalSince(siteControlClosed) > 0.3 else { return }
        _ = try? dispatcher.tryEnqueue { [weak self] in self?.showSiteControlCenter() }
    }

    private func showSiteControlCenter() {
        guard !closing, let siteControlWindow, let window, let host = HWND(bitPattern: hwnd) else { return }
        let url = store.selectedTab(window: windowID)?.tab?.url ?? ""
        let ssl = shownPage?.sslStatus
        let secure = ConnectionSecurity.isSecure(url: url, status: ssl?.status)
        var actions = SiteControlCenterView.Actions()
        actions.perform = { [weak self] action in self?.siteControlAction(action) }
        actions.more = { [weak self] item in self?.siteControlMore(item, url: url) }
        // Windows has two of the three switches: no automatic Picture-in-Picture yet.
        let switches: Set<SiteControlCenter.Setting> = [.developerMode, .blockAdsAndTrackers]
        actions.toggle = { [weak self] setting in
            guard let self else { return }
            SiteControlCenter.toggle(setting, in: &self.store.settings, url: url)
            // The row shows its new state (the same rows, so the same height and place).
            guard self.siteControlShown, let window = self.window else { return }
            self.siteControl.build(url: url, secure: secure, rows: SiteControlCenter.settingRows(self.store.settings, url: url, available: switches),
                                   extensions: self.extensionTiles(scale: window.scale), dark: WinAppearance.isDark)
            self.siteControl.focus()
        }
        actions.runExtension = { [weak self] id in self?.runExtension(id) }
        actions.togglePin = { [weak self] id in
            guard let self else { return }
            ExtensionPins.shared.togglePin(id, profilePath: self.shownProfilePath)
        }
        actions.addExtension = { [weak self] in self?.siteControlMore(.addExtension, url: url) }
        if ssl?.hasCertificate == true {
            actions.showCertificate = { [weak self] in
                guard let self else { return }
                self.hideSiteControlCenter(refocus: true)
                self.shownPage?.showCertificate(owner: self.hwnd)
            }
        }
        siteControl.actions = actions
        siteControl.build(url: url, secure: secure, rows: SiteControlCenter.settingRows(store.settings, url: url, available: switches),
                          extensions: extensionTiles(scale: window.scale), dark: WinAppearance.isDark)
        // Under the sliders, its right edge at theirs, kept on the window.
        let scale = window.scale
        let width = Int32((Double(SiteControlCenter.Metrics.width) * scale).rounded())
        let height = Int32((siteControl.height * scale).rounded())
        var corner = slidersCorner(host: host, scale: scale)
        corner.x = max(0, corner.x - width)
        siteControlWindow.place(origin: PointInt32(x: corner.x, y: corner.y), size: SizeInt32(width: width, height: height))
        siteControlWindow.show { [weak self] in self?.siteControl.focus() }
    }

    /// Under the sliders, on screen: their right edge, 4 DIPs below them (where the Site Control
    /// Center and an extension's popup hang).
    private func slidersCorner(host: HWND, scale: Double) -> POINT {
        // The toolbar's sliders while it shows.
        let onToolbar = topBar == .toolbar ? pageToolbar.sliders : nil
        return corner(under: onToolbar ?? sliders, onToolbar: onToolbar != nil, host: host, scale: scale)
    }

    /// Under `button`, on screen: its right edge, 4 DIPs below it. `onToolbar`: it is in the
    /// toolbar's strip, which starts at the page area's left edge, else in the sidebar column.
    private func corner(under button: Button, onToolbar: Bool, host: HWND, scale: Double) -> POINT {
        var corner = POINT(x: 0, y: 0)
        if let transform = try? button.transformToVisual(nil),
           let origin = try? transform.transformPoint(WindowsFoundation.Point(x: 0, y: 0)) {
            let right = (Double(origin.x) + button.actualWidth) * scale
            let bottom = (Double(origin.y) + button.actualHeight + 4) * scale
            let origin = onToolbar ? (x: window.contentFrame.x, y: Int32(0)) : window.columnOrigin
            corner = POINT(x: Int32(right.rounded()) + origin.x, y: Int32(bottom.rounded()) + origin.y)
        }
        _ = ClientToScreen(host, &corner)
        return corner
    }

    // MARK: Extensions

    /// The profile the page on screen runs in (its extensions are that profile's); nil is Default.
    private var shownProfilePath: String? {
        store.selectedTabID(window: windowID).flatMap { store.profilePath(item: $0) }
    }

    /// The Site Control Center's extension tiles: the page's profile's turned-on extensions, the
    /// pinned ones first in toolbar order, then the rest by name (Arc, PinnedExtensions.menuOrder).
    /// None in a private window, whose off-the-record profile runs none here.
    private func extensionTiles(scale: Double) -> [SiteControlCenterView.ExtensionTile]? {
        guard !isIncognito else { return nil }
        let list = ExtensionList.shared, pins = ExtensionPins.shared
        let path = shownProfilePath
        let ordered = pins.pins.menuOrder(list.enabled(profilePath: path, chromiumCache: store.chromiumCache),
                                          inProfile: ExtensionPins.profile(path), id: \.id, name: \.name)
        return ordered.map {
            SiteControlCenterView.ExtensionTile(id: $0.id, name: $0.name, icon: list.icon($0, points: 16, scale: scale),
                                                pinned: pins.isPinned($0.id, profilePath: path))
        }
    }

    /// The toolbar's pinned extensions (ToolbarView.Pin): none in a private window, as its
    /// Site Control Center has no extensions.
    private func toolbarPins(scale: Double) -> [ToolbarView.Pin] {
        guard !isIncognito else { return [] }
        let list = ExtensionList.shared
        let path = shownProfilePath
        let enabled = list.enabled(profilePath: path, chromiumCache: store.chromiumCache)
        return ExtensionPins.shared.toolbarIDs(profilePath: path, enabled: enabled).compactMap { id in
            enabled.first { $0.id == id }.map { ToolbarView.Pin(id: id, name: $0.name, icon: list.icon($0, points: 16, scale: scale)) }
        }
    }

    /// A click on an extension's tile. Windows has no toolbar for Chrome's popup to hang from,
    /// so the popup page opens in a card of its own, else its options page (ExtensionLaunch).
    /// `anchor`: the pin that was clicked (in the toolbar or not), which the popup hangs from;
    /// else it hangs from the sliders.
    private func runExtension(_ id: String, anchor: (button: Button, onToolbar: Bool)? = nil) {
        hideSiteControlCenter()
        guard !isIncognito else { return }
        let profile = shownProfilePath
        let available = ExtensionList.shared.entries(profilePath: profile, chromiumCache: store.chromiumCache).map(\.launch)
        switch ExtensionLaunch.decide(id, available: available, hasPage: false) {
        case .popupWindow(let url): openExtensionPopup(url, profilePath: profile, anchor: anchor)
        case .openTab(let url): store.createTab(url: url, window: windowID)
        case .nothing, .runAction: break
        }
    }

    private func openExtensionPopup(_ url: String, profilePath: String?, anchor: (button: Button, onToolbar: Bool)? = nil) {
        extensionPopup?.close()
        guard !closing, let window, let host = HWND(bitPattern: hwnd) else { return }
        do {
            let popup = try ExtensionPopup(url: url, profilePath: profilePath, owner: window,
                                           corner: anchor.map { corner(under: $0.button, onToolbar: $0.onToolbar, host: host, scale: window.scale) }
                                               ?? slidersCorner(host: host, scale: window.scale))
            popup.onClose = { [weak self, weak popup] in
                if self?.extensionPopup === popup { self?.extensionPopup = nil }
            }
            popup.openTab = { [weak self] link in
                guard let self else { return }
                self.store.createTab(url: link, select: true, window: self.windowID)
            }
            extensionPopup = popup
        } catch {
            print("Cra: an extension's popup could not open: \(error)")
        }
    }

    /// `refocus`: the page takes the keyboard back if the popover had it (a click elsewhere
    /// already put it where it belongs).
    private func hideSiteControlCenter(refocus: Bool = false) {
        guard siteControlShown, let siteControlWindow else { return }
        let hadFront = GetForegroundWindow() == HWND(bitPattern: siteControlWindow.hwnd)
        siteControlWindow.hide()
        guard refocus, hadFront, !closing, let window = HWND(bitPattern: hwnd) else { return }
        _ = SetForegroundWindow(window)
        focusContent()
    }

    /// Every action closes the popover first, as in Arc.
    private func siteControlAction(_ action: SiteControlCenter.Action) {
        hideSiteControlCenter(refocus: true)
        switch action {
        case .share:
            guard let tab = store.selectedTab(window: windowID), let url = tab.tab?.url, !url.isEmpty else { return }
            share(url: url, title: tab.displayTitle)
        case .copyURL: copyURL(markdown: false)
        case .capture: capture(fullPage: false)
        case .captureFullPage: capture(fullPage: true)
        }
    }

    private func siteControlMore(_ item: SiteControlCenter.MoreItem, url: String) {
        hideSiteControlCenter(refocus: true)
        switch item {
        case .clearCache: shownPage?.clearSiteDataAndReload(cookies: false)
        case .clearCookies: shownPage?.clearSiteDataAndReload(cookies: true)
        case .siteSettings: if let settings = SiteControlCenter.siteSettingsURL(for: url) { store.createTab(url: settings, window: windowID) }
        case .manageExtensions: store.createTab(url: SiteControlCenter.manageExtensionsURL, window: windowID)
        case .addExtension: store.createTab(url: SiteControlCenter.addExtensionURL, window: windowID)
        // The shared Mac menu can offer Boosts; Windows does not request that group yet.
        case .manageBoosts, .newBoost: break
        }
    }

    // MARK: Copy and capture

    private func share(url: String, title: String) {
        WinShell.share(url: url, title: title, owner: hwnd, dispatcher: dispatcher,
                       isValid: { [weak self] in self?.closing == false },
                       onFailure: { [weak self] in self?.showToast(ShareRetry.failureMessage) })
    }

    /// Ctrl+Shift+C (Arc's ⇧⌘C): the page's address; with Alt, as a Markdown link.
    private func copyURL(markdown: Bool) {
        // Arc: "Copy the current tab's URL without trackers" (utm_* and click ids go).
        guard let tab = store.selectedTab(window: windowID), let address = tab.tab?.url, !address.isEmpty else { return }
        let url = CleanURL.withoutTrackers(address)
        guard WinShell.copy(markdown ? "[\(tab.displayTitle)](\(url))" : url) else { return }
        if markdown {
            showToast("Copied URL as Markdown")
        } else {
            let title = tab.displayTitle
            showToast("Copied Current URL", action: ToastView.Action(title: "Share") { [weak self] in
                self?.share(url: url, title: title)
            })
        }
    }

    /// Copy URL as Quote: the page's selection in curly quotes, then a link that scrolls to it
    /// (CleanURL.quote; the Mac's PageCommands.copyURLAsQuote).
    /// Edit ▸ Paste and Go (AppDelegate.pasteAndGo, #610): the copied link as a new tab, other
    /// copied text searched, routed by Air Traffic Control as a typed address is. From the command
    /// bar, so no field has the keys and it never just pastes; a beep when there is nothing to open.
    private func pasteAndGo() {
        guard case .open(let text) = PasteAndGo.outcome(typing: false, clipboard: WinShell.text()) else {
            _ = MessageBeep(0)
            return
        }
        let url = SuggestionEngine.looksLikeURL(text) ? SuggestionEngine.urlFromInput(text) : engine.searchURL(text)
        if !isIncognito, let space = store.settings.space(forTypedURL: url), space != store.focusedSpaceID(window: windowID),
           store.orderedSpaces.contains(where: { $0.id == space }) {
            store.createTab(url: url, in: space, window: windowID)
        } else {
            store.createTab(url: url, window: windowID)
        }
    }

    private func copyURLAsQuote() {
        guard let page = shownPage, let url = store.selectedTab(window: windowID)?.tab?.url, !url.isEmpty else { return }
        page.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak self] result, _ in
            let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let text = (value?["result"] as? [String: Any])?["value"] as? String ?? ""
            guard let self else { return }
            guard let quote = CleanURL.quote(text, url: url) else { return self.showToast("Select Text to Copy as a Quote") }
            if WinShell.copy(quote) { self.showToast("Copied URL as Quote") }
        }
    }

    /// Arc's "Capture this page" and "Capture the full page": the PNG goes on the clipboard and
    /// the toast's Save puts it in a file. Picking an area of the page, as the Mac's capture
    /// overlay does, comes later; this one takes what the page shows.
    private func capture(fullPage: Bool) {
        guard let page = shownPage, !capturing else { return }
        capturing = true
        let shoot: (String) -> Void = { [weak self, weak page] params in
            guard let page else {
                self?.capturing = false
                return
            }
            page.sendDevToolsMethod("Page.captureScreenshot", params: params) { shot, error in self?.finishCapture(shot, error: error) }
        }
        guard fullPage else { return shoot(PageCapture.screenshotParams()) }
        showToast("Capture in Progress")
        page.sendDevToolsMethod("Page.getLayoutMetrics") { [weak self] result, error in
            guard let size = result.flatMap(PageCapture.contentSize(layoutMetrics:)) else {
                self?.finishCapture(nil, error: error)
                return
            }
            shoot(PageCapture.screenshotParams(fullPageWidth: size.width, height: size.height))
        }
    }

    private func finishCapture(_ shot: String?, error: String?) {
        capturing = false
        guard let png = shot.flatMap(PageCapture.png(screenshot:)), WinShell.copy(png: png) else {
            print("Cra: capture failed: \(error ?? "no data")")
            showToast("Capture Failed")
            return
        }
        showToast("Screenshot Copied to Clipboard", action: ToastView.Action(title: "Save") { [weak self] in self?.saveCapture(png) })
    }

    /// The toast's Save: Arc's "Save Capture Image", in Downloads.
    private func saveCapture(_ png: Data) {
        guard let path = WinShell.savePNG(owner: hwnd, title: "Save Capture Image", fileName: PageCapture.fileName(at: Date())) else { return }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            print("Cra: saving a capture failed: \(error)")
            showToast("Failed to Save Capture")
        }
    }

    func showToast(_ text: String, action: ToastView.Action? = nil) {
        guard !closing else { return }
        // It takes the slow-response notice's place, which comes back with the next navigation.
        slowResponseToastTab = nil
        toast.show(text, action: action, theme: store.focusedSpace(window: windowID).theme)
    }

    /// A visible pane still waiting for its first response after ten seconds says so in the
    /// toast, with Stop Loading (SlowResponseNotice, GitHub #256). Runs on every page and store
    /// change and when any visible pane's notice falls due.
    private func syncSlowResponse() {
        guard !closing else { return }
        let now = clock.now
        let live = pages.mapValues { page in
            SlowResponseNotices.Page(phase: LoadingIndicator.Phase(isLoading: page.isLoading, committed: page.hasCommittedLoad),
                                     navigation: page.navigationStarts)
        }
        let state = slowResponses.update(live, visible: paneIDs, focused: shownTabID, now: now)
        slowResponseCheck?.cancel()
        slowResponseCheck = nil
        if let due = state.checkAt {
            slowResponseCheck = clock.after(due.timeIntervalSince(now)) { [weak self] in self?.syncSlowResponse() }
        }
        if let id = state.shown {
            if slowResponseToastTab != id { showSlowResponse(id) }
        } else if slowResponseToastTab != nil {
            slowResponseToastTab = nil
            toast.hide()
        }
    }

    private func showSlowResponse(_ id: UUID) {
        guard let page = pages[id] else { return }
        let url = page.navigatingURL.isEmpty ? store.item(id)?.tab?.url ?? "" : page.navigatingURL
        // The notice belongs to this pane, even while another pane has the keyboard. Set the
        // anchor before ToastView asks pageOnScreen for its position.
        slowResponseToastTab = id
        toast.show(SlowResponseNotice.message(for: url),
                   action: ToastView.Action(title: "Stop Loading") { [weak self] in self?.pages[id]?.stopLoading() },
                   theme: store.focusedSpace(window: windowID).theme,
                   onClose: { [weak self] in
                       // ✕: the page goes on waiting, without the notice.
                       guard let self else { return }
                       self.slowResponses.close(id)
                       if self.slowResponseToastTab == id { self.slowResponseToastTab = nil }
                       // Another pane may already be due, with no further loading event to
                       // wake it. Leave this Close button's input callback before showing it.
                       _ = try? self.dispatcher.tryEnqueue { [weak self] in self?.syncSlowResponse() }
                   })
        // Shown only when the page area is on screen.
        slowResponseToastTab = toast.isShown ? id : nil
    }

    /// The notice's pane, else the focused pane, on screen (the whole page area without a split).
    private func pageOnScreen() -> (left: Int32, top: Int32, right: Int32, scale: Double)? {
        guard let window, let host = HWND(bitPattern: hwnd) else { return nil }
        let frame = (slowResponseToastTab ?? shownTabID).flatMap { paneFrames[$0] } ?? window.contentFrame
        var topLeft = POINT(x: frame.x, y: frame.y)
        _ = ClientToScreen(host, &topLeft)
        return (topLeft.x, topLeft.y, topLeft.x + frame.width, window.scale)
    }
}

// MARK: - Sidebar → window

extension BrowserWindow: SpacesManagerActions {
    func openFromLibrary(tab id: UUID) {
        store.selectTab(id, window: windowID)
        closeLibrary()
    }

    func openFromLibrary(space id: UUID) {
        store.focusSpace(id, window: windowID)
        closeLibrary()
    }

    /// The new space's card joins the page, which stays open (the Mac opens the space editor).
    func newSpaceFromLibrary() {
        guard !isIncognito else { return }
        // The Library covers the sidebar, where Create a Space would open.
        sidebar.newSpaceAtOnce()
    }

    func runCommand(_ id: String) { _ = perform(id) }

    /// Rebuild Profiles from Arc… (ArcProfileRebuilder): its sheets over this window, after the
    /// command bar's key or click that asked.
    func rebuildArcProfiles() {
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { return }
            ArcProfileRebuilder.run(store: self.store) { [weak self] dialog, done in
                guard let self, !self.closing else { return done(nil) }
                dialog.present(over: self.window, completion: done)
            }
        }
    }

    /// Delete Space…: Arc's question first, since the space's tabs and folders are archived; the
    /// last space only says it has to stay (SpaceDeleteConfirmation).
    func confirmDeleteSpace(_ id: UUID) {
        guard let space = store.space(id) else { return }
        guard !closing, deleteSpaceSheet == nil else { return }
        let prompt = SpaceDeleteConfirmation.prompt(title: space.title, spaceCount: store.spaceOrder.count)
        // Arc's dialog sheet, as the Mac asks (AppDialog): Delete in red, Cancel with Escape.
        let sheet = AppDialog(title: prompt.title, message: prompt.message ?? "", actions: prompt.actions)
        deleteSpaceSheet = sheet
        // After the click or key that asked, as the quit question shows.
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { self?.deleteSpaceSheet = nil; return }
            sheet.present(over: self.window) { [weak self] picked in
                guard let self else { return }
                self.deleteSpaceSheet = nil
                if prompt.deletes(picked: picked) { self.store.deleteSpace(id) }
                self.focusContent()
            }
        }
    }
}

extension BrowserWindow: LibraryActions {
    /// The Library takes over the sidebar, 70 DIPs wider for its rail; its search takes the keys.
    func showLibrary(_ page: LibraryPage) {
        guard !closing else { return }
        lastLibraryPage = page
        let opening = libraryPage == nil
        libraryPage = page
        library.show(page)
        // Drawn by the redraw, which also watches what the Library reads from now on (the
        // archive, the downloads, their thumbnails): drawn here, a Remove from Archive or a
        // thumbnail arriving went unseen.
        refresh()
        guard opening else { return }
        commandBar.close()
        hideFindBar()
        hideSiteControlCenter()
        setLibraryShown(true)
        // A hidden sidebar comes out with it, and stays out while it is open (keptOut).
        if !sidebarDocked { floatingSidebar.show() }
        window.focusXAML()
        library.focusSearch()
    }

    func previewMedia(_ files: [MediaLibrary.File], at index: Int) {
        guard !closing else { return }
        // Back to the grid's search once it closes, as the Library was.
        MediaPreviewWin.show(files, at: index, over: window, store: store) { [weak self] in self?.focusLibrary() }
    }

    func focusLibrary() {
        guard libraryPage != nil, !closing else { return }
        window.focusXAML()
        library.focusSearch()
    }

    func closeLibrary() {
        guard libraryPage != nil, !closing else { return }
        libraryPage = nil
        setLibraryShown(false)
        focusContent()
    }

    /// Escape a page didn't use leaves the Library, if the page has the keyboard while it is open.
    /// A shortcut the page left alone runs now (Prefer Websites, Use Both's first press).
    func page(_ page: WebPage, handleUnhandledKey key: KeyPress) -> Bool {
        guard libraryPage != nil, key.keyCode == 0x1B, !key.control, !key.shift, !key.alt, !key.isRepeat else {
            guard !key.isRepeat || key.keyCode == 0x09, let action = WinShortcutRouting.pageLeft(key) else { return false }
            return perform(action.id)
        }
        _ = try? dispatcher.tryEnqueue { [weak self] in self?.closeLibrary() }
        return true
    }

    func restoreArchived(_ id: UUID) {
        guard store.restoreArchived(id, select: false) != nil else { return }
        store.selectTab(id, window: windowID)
        closeLibrary()
    }
}

extension BrowserWindow: SidebarActions {
    func addSplitView() { addSplitPane() }
    /// Set Profile ▸ New Profile… on a space's menu: the space starts ticked.
    func newProfile(forSpace id: UUID) { showNewProfile(ticked: [id]) }

    /// The tab's mute is saved (`Tab.muted` in sidebar.json), so its next page and a relaunch keep it.
    func toggleMute(_ id: UUID) {
        guard let tab = store.item(id)?.tab else { return }
        store.setMuted(id, !tab.muted)
        pages[id]?.setAudioMuted(!tab.muted)
    }

    /// This window's loaded pages for Pause All Media (a sleeping tab has none), each with how
    /// to bring it on screen.
    func mediaPauseTargets() -> [PauseAllMedia.Target] {
        pages.sorted { $0.key.uuidString < $1.key.uuidString }.map { id, page in
            let space = store.spaceID(ofItem: id, window: windowID)
            return PauseAllMedia.Target(page: MediaPause.Page(id: id, window: windowID, space: space,
                                                              profile: space.flatMap { store.space($0)?.profileID }, loaded: true),
                                        web: page, title: store.item(id)?.displayTitle ?? page.currentTitle,
                                        show: { [weak self] in
                                            guard let self, !self.closing else { return }
                                            self.store.selectTab(id, window: self.windowID)
                                            self.activate()
                                        })
        }
    }

    /// Rename…'s field takes the keyboard with its text selected, as the Mac's does.
    func focusRenameField(_ field: TextBox) {
        window.focusXAML()
        _ = try? field.focus(.programmatic)
        try? field.selectAll()
    }

    /// Return, Escape or a click elsewhere ended a rename: keys back to the page.
    func renameEnded() { focusContent() }

    /// Arc's Back to Pinned Page (resetTab): the pinned tab goes back to its pinned page, with its
    /// name and icon, and its page loads it (MainWindowController.resetPinnedTab).
    func resetPinnedTab(_ id: UUID) {
        guard let home = store.resetPinnedTab(id) else { return }
        pages[id]?.loadURL(home)
    }

    /// Edit Pinned Page ▸ Edit… (the Mac's MainWindowController.editPinnedURL, #54): a tab on its
    /// pinned page goes to the new one; one away from it keeps its page.
    func editPinnedURL(_ id: UUID) {
        guard !closing, let window, let tab = store.item(id)?.tab, store.isPinned(id), tab.liveItemURL == nil else { return }
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { return }
            self.editPinnedDialog.present(over: window, url: tab.savedURL, onSave: { [weak self] url in
                guard let self, let before = self.store.item(id)?.tab, self.store.setPinnedURL(id, to: url),
                      before.url == before.savedURL, before.url != url else { return }
                self.pages[id]?.loadURL(url)
            }, onDone: { [weak self] in
                guard let self else { return }
                if let host = HWND(bitPattern: self.hwnd) { _ = SetForegroundWindow(host) }
                self.focusContent()
            })
        }
    }

    /// Arc's Ctrl-click (the Mac's ⌘-click) on the favicon of a pinned tab away from its page,
    /// Separate From Pinned Tab (#139): the page moves to a new Today tab at the top, the pinned
    /// tab goes back to its page and stays open (MainWindowController.separatePinnedTab).
    func separatePinnedTab(_ id: UUID) {
        guard let home = store.separateFromPinnedTab(id)?.home else { return }
        pages[id]?.loadURL(home)
        store.selectTab(id, window: windowID)
    }

    /// Reset all tabs in this Space: every pinned tab of the space in front that is away from its
    /// pinned page, folders included.
    private func resetAllPinnedTabs() {
        let space = store.focusedSpace(window: windowID)
        for t in store.tabs(under: space.pinnedContainerID) where t.tab.map({ $0.url != $0.savedURL }) == true {
            resetPinnedTab(t.id)
        }
    }

    /// Today tabs are archived. Pinned tabs and favorites stay; they unload and return to
    /// their pinned page (Arc's close-on-pinned behaviour, MainWindowController.closeTab).
    func closeTab(_ id: UUID) {
        guard let item = store.item(id), item.isTab else { return }
        if store.isPinned(id) {
            // A pinned split closes as one: every pane unloads and goes back to its page. When it
            // was the open tab, the pages it was on go where Ctrl+Shift+T takes them back from (#566).
            let panes = store.paneTabIDs(for: id)
            let wasSelected = store.selectedTabID(window: windowID).map(panes.contains) ?? false
            for p in store.closePinnedTab(id, wasOpen: wasSelected) {
                pages[p]?.close()
                pages[p] = nil
            }
            // Arc goes back to the tab shown before this one if its page is still loaded, and
            // otherwise shows nothing (CloseSuccessor). The panes were just unloaded, so they
            // don't count.
            if wasSelected { store.selectTab(store.closeSuccessor(ofPinned: id, window: windowID), window: windowID) }
        } else {
            store.archiveTab(id, reason: .manual)
        }
    }

    /// "+ New Tab", Ctrl+T: the command bar, making a new tab.
    func beginNewTab() {
        openCommandBar(.newTab)
    }

    func addPane(toSplit id: UUID) {
        guard let last = store.children(of: id).last(where: \.isTab) else { return }
        store.selectTab(last.id, window: windowID)
        addSplitPane()
    }
}

// MARK: - Chromium → window

extension BrowserWindow: WebPageDelegate {
    func page(_ page: WebPage, didChangeTitle title: String) {
        if let id = tabID(of: page) { store.updateTab(id, title: title) }
    }

    func page(_ page: WebPage, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        if !loading { savePageList(page) }
        syncSlowResponse()
        if page === shownPage { syncToolbar() } else { syncPaneBars() }
        if page === shownPage { syncLoadingBar(animated: true) }
    }

    func page(_ page: WebPage, didReportBackgroundColor hex: String) {
        if page === shownPage { placeLoadingBar() }
    }

    /// Arc's loading bar follows the page in front (LoadingIndicator.Phase): a pulsing pill
    /// before the server answers, the sweep while the page loads, the flash once it has.
    private func syncLoadingBar(animated: Bool) {
        guard let loadingBar, !closing else { return }
        let phase = shownPage.map { LoadingIndicator.Phase(isLoading: $0.isLoading, committed: $0.hasCommittedLoad) } ?? .hidden
        placeLoadingBar()
        loadingBar.set(phase, animated: animated)
    }

    /// Centred over the page area in the window's top 10 DIPs (LoadingIndicator.topBand), over
    /// the developer bar while it shows, else over the page, in ink that shows on it.
    private func placeLoadingBar() {
        guard let loadingBar, !closing, let window, let host = HWND(bitPattern: hwnd) else { return }
        let area = window.contentFrame
        var top = POINT(x: area.x + area.width / 2, y: 0)
        _ = ClientToScreen(host, &top)
        let remembered = store.selectedTab(window: windowID)?.tab?.themeColor
        let ground: LoadingIndicator.Ground = switch topBar {
        case .developer: .developerBar
        case .toolbar: .toolbar(ToolbarColor.hex(reported: nil, remembered: remembered))
        case .none: .page(shownPage?.backgroundColor)
        }
        let light = LoadingIndicator.lightInk(on: ground, themeDark: store.focusedSpace(window: windowID).theme.isDark,
                                              canvasDark: WinAppearance.isDark)
        loadingBar.place(centreX: top.x, top: top.y, scale: window.scale, lightInk: light, visible: !IsIconic(host))
    }

    // MARK: Back and Forward history

    /// The menu opens with the rows read last for this page (none for another page), then fills
    /// in from Chromium's answer (DevTools `Page.getNavigationHistory`, as on the Mac).
    private func openHistoryMenu(_ direction: BackForwardMenu.Direction) {
        fillHistoryMenu(direction)
        guard let page = shownPage else { return }
        page.sendDevToolsMethod("Page.getNavigationHistory") { [weak self, weak page] json, _ in
            guard let self, let page, page === self.shownPage, let json else { return }
            let id = ObjectIdentifier(page)
            if self.historyPage != id {
                self.historyPage = id
                self.historyRows = [:]
            }
            let rows = BackForwardMenu.rows(history: json, direction: direction)
            guard rows != self.historyRows[direction] else { return }
            self.historyRows[direction] = rows
            self.fillHistoryMenu(direction)
        }
    }

    private func fillHistoryMenu(_ direction: BackForwardMenu.Direction) {
        let menu = direction == .back ? backMenu : forwardMenu
        menu.items.clear()
        let current = shownPage.map(ObjectIdentifier.init)
        let rows = current != nil && current == historyPage ? historyRows[direction] ?? [] : []
        guard !rows.isEmpty else {
            let none = UI.menuItem(direction == .back ? "No Earlier Pages" : "No Later Pages") {}
            none.isEnabled = false
            menu.items.append(none)
            return
        }
        for row in rows {
            menu.items.append(UI.menuItem(row.title) { [weak self] in self?.goToHistoryEntry(row.entryID) })
        }
    }

    private func goToHistoryEntry(_ entryID: Int) {
        shownPage?.sendDevToolsMethod("Page.navigateToHistoryEntry", params: #"{"entryId":\#(entryID)}"#) { _, _ in }
    }

    func page(_ page: WebPage, didChangeCommittedLoad committed: Bool) {
        syncSlowResponse()
        if page === shownPage { syncLoadingBar(animated: true) }
    }

    func page(_ page: WebPage, didChangeURL url: String) {
        guard let id = tabID(of: page) else { return }
        store.updateTab(id, url: url)
        if page === shownPage { showAddress(url) }
        // A quiet page that navigates leaves the player; a playlist moving on keeps its card.
        nowPlaying.navigated(id, audible: sidebar.audibleTabIDs.contains(id))
        syncNowPlaying()
    }

    func page(_ page: WebPage, didFinishLoadingURL url: String, statusCode: Int) {
        guard let id = tabID(of: page), !store.isIncognito(item: id) else { return }
        if url.hasPrefix("chrome://settings") { watchClearBrowsingData(page) }
        store.recordVisit(url: url, title: page.currentTitle, profile: store.profileID(item: id))
    }

    /// Chrome's Delete browsing data dialog runs in the page; the command bar's history is Cra's.
    /// Hear its Delete and clear the same history (BrowserManager.watchClearBrowsingData).
    private func watchClearBrowsingData(_ page: WebPage) {
        page.sendDevToolsMethod("Runtime.evaluate", params: BrowsingDataClear.watchParams) { [weak self, weak page] result, _ in
            guard let self, let page, let message = BrowsingDataClear.stringResult(result) else { return }
            if let range = BrowsingDataClear.historyRange(messageJSON: message, now: Date()) { self.store.clearHistory(range) }
            if page.currentURL.hasPrefix("chrome://settings") { self.watchClearBrowsingData(page) }
        }
    }

    /// Kept under the page's host and the tab's own key, as the Mac's BrowserManager does: the tab
    /// takes its own, so tabs on one host keep their icons, across a relaunch too (#211, #291).
    func page(_ page: WebPage, didLoadFavicon png: Data, forURL iconURL: String) {
        guard let id = tabID(of: page), let tab = store.item(id)?.tab,
              let (site, key) = FaviconKey.tabIcon(pageURL: tab.url, current: tab.faviconKey, tabID: id) else { return }
        let persist = !store.isIncognito(item: id)
        Favicons.shared.store(png: png, forKey: site, persist: persist)
        Favicons.shared.store(png: png, forKey: key, persist: persist)
        store.setFaviconKey(id, key)
    }

    func page(_ page: WebPage, didReportThemeColor hex: String) {
        if let id = tabID(of: page) { store.setThemeColor(id, hex) }
    }

    /// In the space of the tab it came from, right below it when that is a Today tab
    /// (SidebarStore.openLinkTab, #202).
    func page(_ page: WebPage, requestsNewTabWithURL url: String, inBackground background: Bool) {
        store.openLinkTab(url, from: tabID(of: page), inBackground: background, window: windowID)
    }

    /// Back (Alt+Left, the header's ←, the toolbar's): the page's own history, else a tab a link
    /// opened, with no page behind, closes and the tab it came from shows again (Arc's
    /// navigateBackToReferrer, #273; MainWindowController.goBack on the Mac).
    private func goBack() {
        guard let page = shownPage else { return }
        guard let id = tabID(of: page) else { return page.goBack() }
        // The saved pages from before a relaunch come before closing to the source tab.
        if savedBack(page) { return }
        switch store.backStep(id, canGoBack: page.canGoBack) {
        case .history: page.goBack()
        case .close(let referrer):
            print("Cra: back closes tab \(id) to the tab it came from")
            store.closeToReferrer(id, referrer: referrer, window: windowID)
        case .none: break
        }
    }

    /// The link menu's Open Link in Split View and, outside a private window, in Little Window.
    func linkMenuExtras(for page: WebPage) -> [LinkMenuExtra] {
        guard let id = tabID(of: page), pages[id] === page else { return [] }
        return LinkMenuExtra.offered(splits: true, incognito: isIncognito)
    }

    /// Open Link in Split View (#257): a pane beside the page's tab, as Alt+Return does from the
    /// command bar (MainWindowController.browserManagerOpenLinkInSplit); Little Window: one for the
    /// link, in the tab's space.
    func page(_ page: WebPage, opensLink url: String, in extra: LinkMenuExtra) {
        // cra:// is Cra's scripting scheme; a page must not drive it.
        guard !url.isEmpty, !url.lowercased().hasPrefix("cra:"), let id = tabID(of: page), store.item(id) != nil else { return }
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { return }
            switch extra {
            case .splitView:
                guard self.store.openLinkInSplit(url, from: id, window: self.windowID) != nil else {
                    self.showToast("Cannot Add New Pane")
                    return
                }
                self.refresh()
            case .littleWindow:
                self.host?.openLinkInLittleWindow(url, space: self.store.spaceID(ofItem: id))
            }
        }
    }

    /// Arc's Peek (PeekTrigger, Settings ▸ Tabs ▸ Links): the link opens over the window and the
    /// tab stays put. Never in a private window.
    func page(_ page: WebPage, opensPeekForURL url: String, shiftClick: Bool, newTab: Bool) -> Bool {
        guard !isIncognito, !closing, !url.lowercased().hasPrefix("cra:"), let id = tabID(of: page), pages[id] === page else { return false }
        let from = page.currentURL.isEmpty ? (store.item(id)?.tab?.url ?? "") : page.currentURL
        guard PeekTrigger.opens(url, from: from, shiftClick: shiftClick, newTab: newTab, fromPinned: store.isPinned(id),
                                settings: store.settings) else { return false }
        // Not from inside Chromium's navigation callback.
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing else { return }
            self.host?.openPeek(url: url, over: self, fromTab: id)
        }
        return true
    }

    func page(_ page: WebPage, popupHostForURL url: String, inBackground background: Bool) -> WebPage? {
        // The popup gets a tab of its own; its page is the host Chromium opens it in.
        // Its tab keeps the one it came from, for Back (#273).
        let source = tabID(of: page)
        let space = source.flatMap { store.spaceID(ofItem: $0) }
        let tab = store.createTab(url: url, in: space, select: false, window: windowID, referrer: source)
        let host = WebPage(popupHostIn: hwnd, frame: contentFrame(), incognito: page.isIncognito, profilePath: page.profilePath,
                           delegate: self)
        livePages.insert(ObjectIdentifier(host))
        host.userInfo = tab.id
        host.isVisible = false
        pages[tab.id] = host
        if !background { store.selectTab(tab.id, window: windowID) }
        return host
    }

    /// Before the page sees a key: the shortcuts that prefer Cra, and Use Both's second press of one the
    /// page kept (Settings ▸ Shortcuts, #374). The rest go to the page and come back through
    /// handleUnhandledKey if it leaves them alone (the Mac's handleReservedKey).
    func page(_ page: WebPage, handleKey key: KeyPress) -> Bool {
        if tabSwitcher?.isOpen == true { return switcherKey(key) }
        guard !key.isRepeat || key.keyCode == 0x09 else { return false }
        let action = WinShortcutRouting.beforePage(key) { [weak self] action, at in self?.watchUseBoth(action, pressedAt: at) }
        guard let action else { return false }
        return perform(action.id)
    }

    /// Use Both: a press the page hasn't handed back by `UseBothPresses.answerTime` was the page's.
    /// Arc's toast says so ("Press Ctrl+W again to Close Tab", Edit the shortcut) and the next press is Cra's.
    private func watchUseBoth(_ action: KeyAction, pressedAt: TimeInterval) {
        useBothWatch = clock.after(UseBothPresses.answerTime) { [weak self] in
            guard let self, !self.closing, let text = WinShortcutRouting.keptText(action, pressedAt: pressedAt) else { return }
            self.showToast(text, action: ToastView.Action(title: "Edit the shortcut") { [weak self] in
                self?.openSettings(pane: .shortcuts)
            })
        }
    }

    /// In DevTools only their own commands, on the page they inspect: every other key is the
    /// frontend's (Ctrl+F searches the panel, Ctrl+R reloads the page from there, as in Chrome).
    func page(_ page: WebPage, handleDevToolsKey key: KeyPress) -> Bool {
        guard !key.isRepeat,
              let chord = KeyChord(windowsVirtualKey: key.keyCode, control: key.control, shift: key.shift, alt: key.alt),
              let action = WinKeyBindings.shared.action(matching: chord) else { return false }
        switch action.id {
        case "devTools": page.runDevTools(.toggle)
        case "jsConsole": page.runDevTools(.console)
        case "inspectElement": page.runDevTools(.inspect)
        default: return false
        }
        return true
    }

    func page(_ page: WebPage, didFindMatches count: Int, activeMatch: Int) {
        guard findVisible, page === shownPage else { return }
        findBar.report(matches: count, active: activeMatch)
    }

    func page(_ page: WebPage, didUpdateDownload download: DownloadInfo) {
        if windowDownloads.insert(download.identifier).inserted {
            // Chrome's glyph would fly from the page's top left to a toolbar Cra hides; the
            // sidebar's downloads button shows the progress (ChromeDownloadAnimation on the Mac).
            cra_hide_download_started_animation()
            if download.state == .inProgress { throwDownloadGlyph() }
        }
        record(download)
    }

    /// Arc's download flight: the glyph thrown from the pointer onto the sidebar's downloads
    /// button (DownloadFlight), while this window is in front with its sidebar out.
    private func throwDownloadGlyph() {
        guard !closing, let host = HWND(bitPattern: hwnd), IsWindowVisible(host), !IsIconic(host),
              GetForegroundWindow() == host, store.window(windowID).sidebarVisible,
              let centre = downloads.glyphCenter else { return }
        let scale = window.scale, column = window.columnOrigin
        var to = POINT(x: Int32((Double(centre.x) * scale).rounded()) + column.x,
                       y: Int32((Double(centre.y) * scale).rounded()) + column.y)
        _ = ClientToScreen(host, &to)
        var from = POINT(x: 0, y: 0)
        guard GetCursorPos(&from) else { return }
        DownloadFlight.launch(owner: UInt(hwnd), from: from, to: to, scale: scale, dispatcher: dispatcher)
    }

    /// Progress and failures show in the downloads list, as in Arc (it has no download toast);
    /// a finished file joins downloads.json (MainWindowController.browserManager(download:)).
    private func record(_ download: DownloadInfo) {
        let path = download.fullPath
        let name = path.isEmpty ? download.suggestedName : URL(fileURLWithPath: path).lastPathComponent
        let history = DownloadHistory.shared
        history.report(id: download.identifier, name: name, path: path, received: download.receivedBytes,
                       total: download.totalBytes, percent: download.percent, complete: download.state == .complete,
                       cancelled: download.state == .cancelled, failed: download.state == .interrupted,
                       paused: download.paused)
        if download.state == .complete, !path.isEmpty, finishedDownloads.insert(download.identifier).inserted {
            history.add(path: path)
        }
        if download.state == .inProgress, downloadWatchdog == nil {
            downloadWatchdog = try? dispatcher.createTimer()
            downloadWatchdog?.interval = TimeSpan(duration: 2 * 10_000_000)
            downloadWatchdog?.isRepeating = true
            downloadWatchdog?.tick.addHandler { [weak self] _, _ in self?.checkStalledDownloads() }
            try? downloadWatchdog?.start()
        }
    }

    /// Chromium goes quiet about a download whose tab closed; the disk says how it ended
    /// (DownloadHistory.settledStalled).
    private func checkStalledDownloads() {
        let history = DownloadHistory.shared
        guard history.isRunning(anyOf: windowDownloads) else {
            try? downloadWatchdog?.stop()
            downloadWatchdog = nil
            return
        }
        let fm = FileManager.default
        func size(_ path: String) -> Int64? {
            guard let value = (try? fm.attributesOfItem(atPath: path))?[.size] else { return nil }
            if let n = value as? UInt64 { return Int64(n) }
            if let n = value as? Int64 { return n }
            return (value as? NSNumber)?.int64Value
        }
        let settled = history.settledStalled(among: windowDownloads, now: Date(), fileSize: size,
                                             partialExists: { fm.fileExists(atPath: $0 + ".crdownload") })
        for (t, outcome) in settled {
            let size: Int64, state: DownloadInfo.State
            switch outcome {
            case .complete(let n): (size, state) = (n, .complete)
            case .cancelled: (size, state) = (0, .cancelled)
            }
            record(DownloadInfo(identifier: t.id, url: "", fullPath: t.path, suggestedName: t.name, receivedBytes: size,
                                totalBytes: t.total, percent: state == .complete ? 100 : t.percent, state: state))
        }
    }

    func page(_ page: WebPage, requestsPermissionForOrigin origin: String, kinds: PermissionKinds,
              answer: @escaping (Bool) -> Void) {
        guard !closing else { return answer(false) }
        let request = PagePermission(page: WeakPage(page), origin: origin, kinds: kinds, answer: answer)
        if permissions.add(request, tabShown: page.isVisible) { showAskingPermission() }
    }

    /// A click into another pane focuses it (Arc: the split's focusItemID follows the click). The
    /// bridge reports every mouse press in a page as well as Chromium's focus, since a page that
    /// once focused itself reports no focus on the next click into it.
    /// Not while a redraw is waiting: the panes on screen are then the old selection's, and a
    /// stale page taking the keyboard would select its tab again over the one just picked.
    /// A new page's own first focus, without a click, gives the keyboard back to the focused pane.
    func pageDidReceiveFocus(_ page: WebPage) {
        guard !closing else { return }
        if newPages[ObjectIdentifier(page)] == nil, handKeyboardToPeek() { return }
        if let made = newPages.removeValue(forKey: ObjectIdentifier(page)), Date().timeIntervalSince(made) < Self.newPageFocusWindow,
           !Self.mouseButtonDown, page !== shownPage {
            // After any redraw already waiting, which may change the focused pane.
            _ = try? dispatcher.tryEnqueue { [weak self, weak page] in
                guard let self, !self.closing, let shown = self.shownPage, shown !== page else { return }
                shown.setFocused(true)
            }
            return
        }
        guard !refreshQueued, let id = tabID(of: page), id != store.selectedTabID(window: windowID),
              paneIDs.contains(id) else { return }
        store.selectTab(id, window: windowID)
    }

    /// A Peek over the window keeps the keyboard while it is up: the window or a page of its
    /// taking it (a redraw, Chromium's own focus) gives it back, a turn later, so Escape and the
    /// shortcuts go to the card. Not while a button is down (a click: the title bar's, or the Peek's catcher
    /// over a page), nor for a page just made, whose tab the Peek opened as it goes (Ctrl+O).
    private func handKeyboardToPeek() -> Bool {
        guard host?.hasShowingPeek(over: self) == true, !Self.mouseButtonDown else { return false }
        _ = try? dispatcher.tryEnqueue { [weak self] in
            guard let self, !self.closing, !Self.mouseButtonDown else { return }
            self.host?.focusPeek(over: self)
        }
        return true
    }

    /// The left, right or middle button is down: the focus came from a click.
    private static var mouseButtonDown: Bool { [Int32(0x01), 0x02, 0x04].contains { GetAsyncKeyState($0) < 0 } }

    /// How long after it is made a page's unasked focus is still Chromium's own.
    private static let newPageFocusWindow: TimeInterval = 2

    func pageDidClose(_ page: WebPage) {
        livePages.remove(ObjectIdentifier(page))
        pageLists[ObjectIdentifier(page)] = nil
        pageEntryCounts[ObjectIdentifier(page)] = nil
        newPages[ObjectIdentifier(page)] = nil
        if closing {
            // After this callback: it comes from inside CEF's OnBeforeClose, and destroying the
            // pages' parent window there crashed libcef.
            if canFinishClosing {
                _ = try? dispatcher.tryEnqueue { [weak self] in self?.finishClosing() }
            }
            return
        }
        // Chromium dismissed its requests; the prompt moves on if it was asking for this page.
        if permissions.remove(where: { $0.page.page === page }).wasAsking {
            permissionWindow?.hide()
            askNextPermission()
        }
        guard let id = tabID(of: page), pages[id] === page else { return }
        pages[id] = nil
        // window.close(): the page's tab goes as a closed tab would.
        if page.closedByPage { closeTab(id) }
    }
}

/// A page held without keeping it alive (a permission request waiting its turn).
struct WeakPage {
    weak var page: WebPage?
    init(_ page: WebPage) { self.page = page }
}

/// A page's permission request waiting in `BrowserWindow.permissions`.
struct PagePermission {
    let page: WeakPage
    let origin: String
    let kinds: PermissionKinds
    let answer: (Bool) -> Void
}

// MARK: - A sidebar tab dropped onto the page

/// Arc's drag-to-split (the Mac's PageSplitDrop): a sidebar tab dragged over the panes proposes a
/// split where it would land (CraCore's SplitDropProposal), shown by a tinted window over that
/// part of the page, and letting go makes it (SplitDrop.drop). The sidebar follows the drag
/// (SidebarDrag.swift) and asks here while the pointer is off the sidebar.
extension BrowserWindow {
    /// The region id the proposal's layout gives the drop region.
    private static let splitDropRegion = UUID()

    /// The panes laid out in DIPs from the page area's bottom left, y up (the proposal's
    /// coordinates), with the drop region in them when `insert` is given.
    private func splitDropFrames(inserting insert: SplitDropProposal.Insert?) -> [UUID: CGRect] {
        let area = window.contentFrame, scale = window.scale
        let split = paneIDs.first.flatMap { store.splitContaining($0) }
        let factors = SplitPaneLayout.normalizedFactors(ids: paneIDs, stored: split?.split?.widthFactors ?? [:])
        var panes = paneIDs.map { SplitPaneLayout.Pane(id: $0, factor: factors[$0] ?? 1 / CGFloat(max(1, paneIDs.count))) }
        var orientation = paneOrientation
        if let insert {
            panes = SplitDropProposal.panes(panes, inserting: Self.splitDropRegion, at: insert)
            if paneIDs.count <= 1 { orientation = insert.orientation }
        }
        return SplitPaneLayout(panes: panes, orientation: orientation,
                               containerSize: CGSize(width: Double(area.width) / scale, height: Double(area.height) / scale),
                               backingScaleFactor: CGFloat(scale), flipped: false).compute().frames
    }

    /// The pointer moved with sidebar tab `id` off the sidebar: whether the panes offer a split
    /// there (and the window shows it). `before`: the tab open before the press that started the
    /// drag (the press opened the dragged one).
    func splitDragMoved(tab id: UUID, before: UUID?) -> Bool {
        guard let window, !closing, store.item(id)?.isTab == true, !paneIDs.isEmpty, let host = HWND(bitPattern: hwnd) else {
            clearSplitDrop()
            return false
        }
        var p = POINT()
        guard GetCursorPos(&p) else { return false }
        _ = ScreenToClient(host, &p)
        let area = window.contentFrame, scale = window.scale
        let size = CGSize(width: Double(area.width) / scale, height: Double(area.height) / scale)
        let point = CGPoint(x: Double(p.x - area.x) / scale, y: size.height - Double(p.y - area.y) / scale)
        var swapTo: UUID?
        if splitDropSwap == nil {
            switch SplitDrop.showing(dragging: id, panes: paneIDs, before: before, store: store) {
            case .refused:
                clearSplitDrop()
                return false
            case .swap(let to):
                swapTo = to
            case .asIs:
                break
            }
        }
        let region = splitDropTarget?.insert.flatMap { splitDropFrames(inserting: $0)[Self.splitDropRegion] }
        guard let proposal = SplitDropProposal.propose(at: point, ids: paneIDs, frames: splitDropFrames(inserting: nil), orientation: paneOrientation,
                                                       area: CGRect(origin: .zero, size: size), region: region, current: splitDropTarget,
                                                       sidebarSide: true, sidebarOn: window.sidebarSide) else {
            clearSplitDrop()
            return false
        }
        if let swapTo {
            // Arc shows the page from before the press again and splits with it.
            splitDropSwap = (id, swapTo)
            store.selectTab(swapTo, window: windowID)
            refresh()
        }
        splitDropTarget = proposal
        showSplitDropRegion(proposal)
        return true
    }

    /// The drag left the page, or ended: `drop` lets go of tab `id` where the split was offered.
    func splitDragEnded(tab id: UUID, drop: Bool) {
        let target = splitDropTarget
        if drop, let target, store.item(id) != nil {
            splitDropTarget = nil
            splitDropSwap = nil
            removeSplitDropOverlay()
            if SplitDrop.drop(.tab(id), at: target, panes: paneIDs, splitOrientation: paneOrientation, store: store, window: windowID) != nil {
                refresh()
                return
            }
        }
        clearSplitDrop()
    }

    /// Takes the region away and shows the dragged tab again.
    private func clearSplitDrop() {
        splitDropTarget = nil
        removeSplitDropOverlay()
        guard let swap = splitDropSwap else { return }
        splitDropSwap = nil
        if store.item(swap.dragged) != nil {
            store.selectTab(swap.dragged, window: windowID)
            refresh()
        }
    }

    private func removeSplitDropOverlay() {
        guard splitDropOverlay != 0 else { return }
        cra_overlay_destroy(splitDropOverlay)
        splitDropOverlay = 0
    }

    /// Tints the region a new pane would take, or the pane a drop would replace.
    private func showSplitDropRegion(_ target: SplitDropProposal.Target) {
        guard let window, let host = HWND(bitPattern: hwnd) else { return }
        let area = window.contentFrame, scale = window.scale
        var rect: PixelRect?
        switch target {
        case .insert(let insert):
            if let r = splitDropFrames(inserting: insert)[Self.splitDropRegion] {
                let height = Double(area.height) / scale
                func px(_ v: CGFloat) -> Int32 { Int32((Double(v) * scale).rounded()) }
                rect = PixelRect(x: area.x + px(r.minX), y: area.y + Int32(((height - Double(r.maxY)) * scale).rounded()),
                                 width: px(r.width), height: px(r.height))
            }
        case .replace(let index):
            rect = paneIDs.indices.contains(index) ? paneFrames[paneIDs[index]] : nil
        }
        guard let rect else { return removeSplitDropOverlay() }
        var origin = POINT(x: rect.x, y: rect.y)
        _ = ClientToScreen(host, &origin)
        if splitDropOverlay == 0 {
            // Cra's blue (brand), see-through, over the page; it takes no clicks while the drag holds the mouse.
            splitDropOverlay = cra_overlay_create(UInt(hwnd), 0x3F6DF5, 70, nil, nil)
        }
        cra_overlay_place(splitDropOverlay, origin.x, origin.y, rect.width, rect.height, 0)
    }
}

