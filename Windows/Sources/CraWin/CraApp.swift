import CraCEFWin
import CraCore
import Foundation
import Observation
import WinAppSDK
import WinSDK
import WinUI

/// The Windows app: starts Chromium, loads the shared SidebarStore from %LOCALAPPDATA%\Cra
/// (the Mac's data folder layout, read by the same CraCore code) and opens a BrowserWindow for
/// each window session it saved (AppDelegate's mainWindows on the Mac).
@main
public final class CraApp: SwiftApplication {
    // XAML objects can only be made once the app is launched, on its UI thread (making them in
    // init fails with RPC_E_WRONG_THREAD).
    @MainActor private var store: SidebarStore?
    @MainActor private var windows: WindowList?
    @MainActor private var clock: WinScheduler?
    /// Auto-archive, as the Mac runs it (AppComposition): kept until the app quits.
    @MainActor private var periodic: [ScheduledWork] = []
    /// New Little Window's key from any app (Settings ▸ Tabs).
    @MainActor private var hotkey: GlobalHotkey?
    /// Settings ▸ Advanced ▸ "Keep Cra in the notification area": there while the setting is on.
    @MainActor private var notificationAreaIcon: NotificationAreaIcon?

    public required init() {
        super.init()
        unhandledException.addHandler { _, args in
            print("Unhandled exception: \(args?.message ?? "")")
        }
    }

    /// Chromium's windows bypass WinUI's input routing (MessageLoop).
    override public class var runLoop: SwiftApplication.RunLoop { MessageLoop.run }

    override public func onShutdown(exitCode: Int32) {}

    override public func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        guard startChromium() else {
            // Another Cra already runs on this profile and was handed this launch.
            // (Not `exit`: inside an Application that names its own exit() method.)
            if cra_cef_another_instance_was_notified() != 0 { ExitProcess(0) }
            print("Chromium did not start")
            return
        }
        guard let dispatcher = try? WinAppSDK.DispatcherQueue.getForCurrentThread() else {
            print("No dispatcher queue on the UI thread")
            return
        }
        // Saved and shut down while XAML is still up; then the process ends (MessageLoop.finish).
        MessageLoop.willQuit = { [weak self] in
            onMain {
                self?.windows?.archiveLittleWindows()
                self?.windows?.saveFrames()
                self?.store?.saveAll()
            }
            cra_cef_shutdown()
            MessageLoop.finish()
        }
        onMain {
            // Unbuffered, so "Cra:" lines reach a redirected stdout even when the process ends
            // without flushing (PR #37's PC test saw none).
            setvbuf(stdout, nil, _IONBF, 0)
            CoreLog.fault = { print("Cra fault: \($0)") }
            let clock = WinScheduler(queue: dispatcher)
            let deleted = DeletedProfiles(directory: WinPaths.supportDir, chromiumCache: WinPaths.chromiumCache)
            let store = SidebarStore(directory: WinPaths.supportDir, chromiumCache: WinPaths.chromiumCache, clock: clock,
                                     onProfileDeleted: deleted.schedule)
            store.runAutoArchive()
            periodic = [clock.every(30 * 60) { store.runAutoArchive() }]
            // Saved back and forward lists of tabs that are gone, other than the latest closed (#273).
            PageListStore.shared.prune(keeping: PageHistory.kept(sidebarTabs: Set(store.allTabs().map(\.id)),
                                                                 archive: store.archive.map(\.id)))
            self.clock = clock
            self.store = store
            startContentBlocking(store: store, clock: clock)
            let windows = WindowList(store: store, dispatcher: dispatcher)
            self.windows = windows
            // A copy in Extensions/ removed in chrome://extensions goes (ExtensionCopyRemovals): each
            // profile's extensions are read once they are up, then on every change.
            ExtensionList.shared.profilePaths = { [weak store] in
                guard let store else { return [nil] }
                return [nil] + store.profiles.map { store.profilePath(profile: $0.id) }
            }
            periodic.append(clock.after(10) { ExtensionList.shared.dropRemovedCopies() })
            let firstRun = Onboarding.isNeeded(hasSeenImportPrompt: store.settings.hasSeenImportPrompt, tabCount: store.allTabs().count)
            // Arc's "When opening Arc, restore windows from previous session", off: one window
            // comes back (AppDelegate on the Mac).
            if !store.settings.restoreWindows { store.keepOnlyActiveWindow() }
            // Settings ▸ Advanced "Start on a new tab": the window in front opens on no tab, before
            // any page is made, so the last page isn't loaded only to be hidden. Not when another
            // app started Cra for a link: its tab is what the window shows. Windows has no update
            // restart.
            let launch = LaunchStart.launch(firstRun: firstRun, automaticUpdate: false,
                                            withLinks: !ExternalLink.links(inArguments: Self.launchArguments()).isEmpty)
            let startOnNewTab = LaunchStart.startsOnNewTab(enabled: store.settings.startOnNewTab, launch: launch)
            if startOnNewTab { store.selectTab(nil, window: store.activeWindowID) }
            windows.restore()
            // A fresh install: the onboarding on a card over the first window (the Mac shows its
            // own window first). Seen once it ends, so quitting halfway brings it back.
            if firstRun {
                windows.windows.first?.showOnboarding()
            } else if startOnNewTab {
                // As Ctrl+T: the command bar makes the new tab, Escape leaves the window empty.
                windows.windowInUse?.openCommandBar(.newTab)
            }
            observeGlobalShortcut(store: store, windows: windows)
            observeNotificationArea(store: store, windows: windows)
            openLinksFromOtherApps(windows: windows)
            openStrayPages(windows: windows, store: store)
            DefaultBrowser.updateRegistrationIfMoved()
            DefaultBrowser.registerScheme()
        }
    }

    /// Links another app opened Cra with: on this launch's command line, and on later launches
    /// that Chromium's process singleton hands to this one (`Cra.exe --single-argument <url>`,
    /// as the default browser's registration runs it, see DefaultBrowser).
    @MainActor
    private func openLinksFromOtherApps(windows: WindowList) {
        Self.relaunched = { [weak windows] arguments in
            let links = ExternalLink.links(inArguments: arguments)
            // Cra started again from the Start menu or the taskbar: its window comes forward.
            if links.isEmpty { windows?.showLastWindow() }
            for url in links { windows?.openExternal(url) }
        }
        cra_cef_set_relaunch_handler(nil) { _, arguments, count in
            let list = (0..<count).compactMap { i in arguments?[i].map { String(cString: $0) } }
            onMain { CraApp.relaunched?(list) }
        }
        for url in ExternalLink.links(inArguments: Self.launchArguments()) { windows.openExternal(url) }
    }

    @MainActor private static var relaunched: (([String]) -> Void)?

    /// Pages Chromium opens in windows of its own (an extension's options or welcome page)
    /// become tabs (WindowList.openExtensionPage); Chrome's window is closed unseen. Cra's own
    /// extensions count as new on every launch, so their welcome pages right after it are
    /// dropped unless one of them is new since the last launch (ExtensionStartUpPages).
    @MainActor
    private func openStrayPages(windows: WindowList, store: SidebarStore) {
        let startUp = ExtensionStartUpPages.launch(at: Date(), installed: ExtensionFolders.loadable(in: WinPaths.extensions).map(\.lastPathComponent),
                                                   directory: WinPaths.supportDir)
        Self.strayPage = { [weak windows, weak store] url, profile in
            guard let windows, let store else { return }
            let isOpen = store.allTabs().contains { $0.tab?.url == url }
            if startUp.drops(at: Date(), isOpen: isOpen) {
                print("Cra: dropped start-up page from an extension: \(url)")
                return
            }
            windows.openExtensionPage(url, profile: profile)
        }
        cra_cef_set_stray_page_handler(nil) { _, url, profile in
            guard let url else { return }
            let link = String(cString: url), folder = profile.map { String(cString: $0) } ?? "Default"
            onMain { CraApp.strayPage?(link, folder) }
        }
    }

    @MainActor private static var strayPage: ((String, String) -> Void)?

    /// This launch's arguments after the program; with `--single-argument` (Chrome's switch for
    /// a link from the shell), everything after it is one argument, spaces and quotes included,
    /// so a link can't add switches or links of its own.
    private static func launchArguments() -> [String] {
        guard let line = GetCommandLineW() else { return Array(CommandLine.arguments.dropFirst()) }
        let raw = String(decodingCString: line, as: UTF16.self)
        if let r = raw.range(of: " --single-argument ") {
            return [String(raw[r.upperBound...])]
        }
        return Array(CommandLine.arguments.dropFirst())
    }

    /// Arc's "Open Little Arc when I press ⌥⌘N" (#195), Ctrl+Alt+N here: New Little Window's key
    /// from any app, following the setting and the key's binding (AppDelegate.observeGlobalShortcut).
    @MainActor
    private func observeGlobalShortcut(store: SidebarStore, windows: WindowList) {
        let hotkey = GlobalHotkey { [weak windows] in windows?.newLittleWindow() }
        self.hotkey = hotkey
        func follow() {
            let chord = withObservationTracking {
                GlobalShortcut.registrable(WinKeyBindings.shared.action("newLittleWindow")?.shortcuts ?? [],
                                           enabled: store.settings.littleWindowShortcutEverywhere)
            } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { follow() } }
            }
            hotkey.set(chord)
        }
        follow()
    }

    /// The Mac's observeMenuBarMode (#231): the notification-area icon follows the setting. Its
    /// click and New Window bring back the window the last close put away (its session, as after
    /// a launch); turned off with no window open, that window comes back, or nothing of Cra would
    /// be left to click.
    @MainActor
    private func observeNotificationArea(store: SidebarStore, windows: WindowList) {
        func follow() {
            let on = withObservationTracking { store.settings.keepInMenuBar } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { follow() } }
            }
            if on, notificationAreaIcon == nil {
                notificationAreaIcon = NotificationAreaIcon(perform: { [weak windows] id in
                    guard let windows else { return }
                    switch id {
                    case "newWindow" where !windows.windows.contains(where: { !$0.isStandalone }), "show": windows.showLastWindow()
                    case "newWindow": windows.openNewWindow(incognito: false)
                    case "newIncognitoWindow": windows.openNewWindow(incognito: true)
                    case "newLittleWindow": windows.newLittleWindow()
                    default: _ = windows.perform(id)
                    }
                }, quit: { [weak windows] in windows?.quitFromNotificationArea() })
            } else if !on, let icon = notificationAreaIcon {
                icon.remove()
                notificationAreaIcon = nil
                if windows.isEmpty { windows.showLastWindow() }
            }
        }
        follow()
    }

    /// Ad and tracker blocking (Settings ▸ Privacy, the Site Control Center's switch, the
    /// onboarding's checkbox) and cookie banner hiding (Settings ▸ Privacy), as
    /// AppDelegate.startContentBlocking runs the first: the bundled list
    /// (blocklist\domains.txt beside Cra.exe, resources/blocklist in the repo) parsed off the
    /// UI thread, the switch following the setting.
    @MainActor
    private func startContentBlocking(store: SidebarStore, clock: WinScheduler) {
        // Before windows.restore creates any pages: user edits and Web Audio need recording at
        // document start, rather than being discovered after the page has already run its scripts.
        cra_cef_set_document_start_script(TabSleepProbe.documentStartScript)
        // Cra's own list with the ones added in Settings ▸ Privacy ▸ Block lists (#507), handed to
        // the engine once the kept copies are read, and again as lists are added, fetched or removed.
        func followBlockLists() {
            let addresses = withObservationTracking { store.settings.customBlocklists } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { followBlockLists() } }
            }
            WinBlockLists.shared.set(addresses: addresses, clock: clock)
        }
        followBlockLists()
        // For the log a PC test reads: 0 means the list is missing from the build.
        _ = clock.after(5) { print("Cra: ad and tracker list: \(cra_cef_blocked_domain_count()) domains") }
        func follow() {
            let (ads, banners) = withObservationTracking { (store.settings.blockAdsAndTrackers, store.settings.blockCookieBanners) } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { follow() } }
            }
            cra_cef_set_content_blocking(ads ? 1 : 0)
            // Arc's Block Cookie Banners: the banners hidden by a stylesheet each page adopts as
            // it commits (BrowserManager's cookieBannerCSS on the Mac).
            cra_cef_set_page_start_script(banners ? CookieBanners.pageScript : "")
        }
        follow()
        // The page menu's "Open Link in New Tab": behind the page as in Arc unless Settings ▸
        // Tabs says to switch (AppDelegate.observeLinkMenu, #276).
        func followLinkMenu() {
            let switches = withObservationTracking { store.settings.openLinksInForeground } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { followLinkMenu() } }
            }
            cra_cef_set_link_menu_background(LinkMenu.item(switchesToTab: switches).opensInBackground ? 1 : 0)
        }
        followLinkMenu()
        // Settings ▸ Privacy ▸ Always use secure connections (Chrome's HTTPS-only mode).
        func followHttpsOnly() {
            let on = withObservationTracking { store.settings.httpsOnly } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { followHttpsOnly() } }
            }
            cra_cef_set_https_only(on ? 1 : 0)
        }
        followHttpsOnly()
        // View ▸ Appearance: what websites see, and Light or Dark turn Cra's own Settings and
        // Site Control Center too, as on the Mac (AppDelegate's websiteAppearance observer, #362).
        func followWebsiteAppearance() {
            let appearance = withObservationTracking { store.settings.websiteAppearance } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { followWebsiteAppearance() } }
            }
            WinAppearance.forcedDark = appearance.forcesDark
            cra_cef_set_website_appearance(Int32(appearance.chromiumMode))
        }
        followWebsiteAppearance()
        // Settings ▸ Advanced ▸ Allow window dragging from the top of webpages (PageTopDrag).
        // Windows' pages have no toolbar over them, so the band is the whole reach.
        func followPageTopDrag() {
            let on = withObservationTracking { store.settings.pageTopWindowDrag } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { followPageTopDrag() } }
            }
            cra_cef_set_page_top_drag(on ? PageTopDrag.band(barHeight: 0) : 0, PageTopDrag.trailingInset)
        }
        followPageTopDrag()
        // Settings ▸ Profiles ▸ Download location: the folder (or Windows' Save dialog) each
        // profile's downloads use (DownloadDestinations on the Mac).
        func followDownloadLocations() {
            let lines = withObservationTracking { DownloadLocation.bridgeLines(store.settings.downloadLocations, profiles: store.profiles) } onChange: {
                onMain { _ = try? WinAppSDK.DispatcherQueue.getForCurrentThread()?.tryEnqueue { followDownloadLocations() } }
            }
            cra_cef_set_download_locations(lines)
        }
        followDownloadLocations()
    }

    private static var exeFolder: URL { URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent() }

    private func startChromium() -> Bool {
        let helper = Self.exeFolder.appendingPathComponent("CraHelper.exe").path
        // The steps that change the data folder run only when no other Cra holds it (#299): a
        // second launch, a link from another app, is handed to the Cra already running and goes.
        let lock = DataFolderOwner.WindowsLockFile(rawValue: WinPaths.native(WinPaths.chromiumCache).withCString { cra_cef_data_folder_lock_state($0) }) ?? .otherError
        if DataFolderOwner.isFree(windowsLockFile: lock) {
            CrashRecovery.prepare(cache: WinPaths.chromiumCache)
            // Deleted profiles' folders, while Chromium has none of them open.
            DeletedProfiles(directory: WinPaths.supportDir, chromiumCache: WinPaths.chromiumCache).run()
            // Passwords and sign-ins an import staged go in while no Chromium has the profile open.
            CredentialImport.applyPending(root: WinPaths.chromiumCache)
            // The desktop apps' native messaging hosts (1Password, Bitwarden…), registered for
            // Chrome, Edge or Brave, where Cra's Chromium finds them.
            NativeMessagingHostsWin.mirror()
        } else {
            print("Cra: the data folder is held (\(lock)); launch steps left to the Cra running on it")
        }
        // Cra's own unpacked extensions (Settings ▸ Extensions), as Windows paths.
        let folders = ExtensionFolders.loadable(in: WinPaths.extensions).map(WinPaths.native)
        cra_cef_set_extension_folders(ExtensionFolders.commandLineValue(paths: folders) ?? "")
        let cache = WinPaths.chromiumCache.path
        let log = WinPaths.log.path
        // Chromium's language follows Windows' display language, as Chrome's does: its own
        // pages, dialogs and menus, the voice for speech without a lang (#167), pages' default
        // date format and a new profile's Accept-Language. Without it CEF is en-US.
        let locale = WinLanguages.chromiumLocale(exeFolder: Self.exeFolder) ?? ""
        CoreLog.note("chromium locale: \(locale.isEmpty ? "en-US (default)" : locale) for \(WinLanguages.preferred.prefix(3).joined(separator: ","))")
        return helper.withCString { h in
            cache.withCString { c in
                log.withCString { l in
                    "Cra/1.0".withCString { product in
                        locale.withCString { lang in
                            var settings = CraCEFSettings()
                            settings.helper_path = h
                            settings.cache_root = c
                            settings.log_path = l
                            settings.user_agent_product = product
                            settings.locale = lang
                            return cra_cef_initialize(&settings) != 0
                        }
                    }
                }
            }
        }
    }
}
