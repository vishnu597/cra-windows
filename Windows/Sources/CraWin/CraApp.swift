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
            CoreLog.fault = { print("Cra fault: \($0)") }
            let clock = WinScheduler(queue: dispatcher)
            let deleted = DeletedProfiles(directory: WinPaths.supportDir, chromiumCache: WinPaths.chromiumCache)
            let store = SidebarStore(directory: WinPaths.supportDir, chromiumCache: WinPaths.chromiumCache, clock: clock,
                                     onProfileDeleted: deleted.schedule)
            store.runAutoArchive()
            periodic = [clock.every(30 * 60) { store.runAutoArchive() }]
            self.clock = clock
            self.store = store
            let windows = WindowList(store: store, dispatcher: dispatcher)
            self.windows = windows
            windows.restore()
            observeGlobalShortcut(store: store, windows: windows)
            openLinksFromOtherApps(windows: windows)
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

    private func startChromium() -> Bool {
        let exe = CommandLine.arguments[0]
        let helper = URL(fileURLWithPath: exe).deletingLastPathComponent().appendingPathComponent("CraHelper.exe").path
        CrashRecovery.prepare(cache: WinPaths.chromiumCache)
        // Deleted profiles' folders, while Chromium has none of them open.
        DeletedProfiles(directory: WinPaths.supportDir, chromiumCache: WinPaths.chromiumCache).run()
        // Passwords and sign-ins an import staged go in while no Chromium has the profile open
        // (another Cra holding it keeps them waiting).
        CredentialImport.applyPending(root: WinPaths.chromiumCache)
        let cache = WinPaths.chromiumCache.path
        let log = WinPaths.log.path
        return helper.withCString { h in
            cache.withCString { c in
                log.withCString { l in
                    "Cra/1.0".withCString { product in
                        var settings = CraCEFSettings()
                        settings.helper_path = h
                        settings.cache_root = c
                        settings.log_path = l
                        settings.user_agent_product = product
                        return cra_cef_initialize(&settings) != 0
                    }
                }
            }
        }
    }
}
