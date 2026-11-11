import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var openedURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        openedURLs.append(contentsOf: urls)
    }
}

/// App policies tested without browser windows or Chromium.
@main
enum PolicyTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        extensionLaunch()
        featureFlags()
        liveScheduler()
        try webHandoff()
        print("Policies: \(checks) checks passed")
    }

    @MainActor
    private static func webHandoff() throws {
        let plist = try Data(contentsOf: URL(fileURLWithPath: "resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        expect((info?["NSUserActivityTypes"] as? [String])?.contains(NSUserActivityTypeBrowsingWeb) == true,
               "macOS can offer Cra for web Handoff")

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let receiver = AppDelegate()
        let delegate: NSApplicationDelegate = receiver
        let web = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        let other = NSUserActivity(activityType: "com.example.other")
        expect(delegate.application?(app, willContinueUserActivityWithType: web.activityType) == true, "accept a web Handoff")
        expect(delegate.application?(app, willContinueUserActivityWithType: other.activityType) == false, "decline unrelated activities")

        func resume(_ activity: NSUserActivity) -> Bool? {
            delegate.application?(app, continue: activity, restorationHandler: { _ in })
        }
        expect(resume(web) == false, "a missing webpage cannot be continued")
        web.webpageURL = URL(string: "https:/missing-host")
        expect(resume(web) == false, "a web address without a host is ignored")
        let urls = ["http://example.test/", "https://example.test/a%20b?q=1#part"].map { URL(string: $0)! }
        other.webpageURL = urls[0]
        expect(resume(other) == false, "a webpage on an unrelated activity is ignored")
        for url in urls {
            web.webpageURL = url
            expect(resume(web) == true, "continue a handed-off web page")
        }
        expect(receiver.openedURLs == urls, "only the accepted pages reach normal URL opening, once each and intact")
    }

    /// #41: a click never reaches an extension turned off in chrome://extensions (Chromium crashed
    /// on it). #22: nor one the page's profile doesn't have; that click does nothing.
    // promise: #22 #41
    private static func extensionLaunch() {
        typealias E = ExtensionLaunch.Extension
        let popup = E(id: "pop", popupPath: "popup.html", optionsPath: "options.html")
        let options = E(id: "opt", popupPath: nil, optionsPath: "settings.html")
        let bare = E(id: "bare")
        let off = E(id: "off", popupPath: "popup.html", enabled: false)
        let all = [popup, options, bare, off]
        expect(ExtensionLaunch.decide("pop", available: all, hasPage: true) == .runAction, "with a page, Chrome runs the action")
        expect(ExtensionLaunch.decide("off", available: all, hasPage: true) == .nothing,
               "a click never reaches an extension turned off in chrome://extensions")
        expect(ExtensionLaunch.decide("off", available: all, hasPage: false) == .nothing, "not even without a page")
        expect(ExtensionLaunch.fallback(off) == .nothing, "nor when Chrome's action failed")
        expect(ExtensionLaunch.decide("gone", available: all, hasPage: true) == .nothing, "an extension of another profile does nothing")
        expect(ExtensionLaunch.decide("pop", available: all, hasPage: false) == .popupWindow(url: "chrome-extension://pop/popup.html"),
               "no page: the popup page in its own window")
        expect(ExtensionLaunch.decide("opt", available: all, hasPage: false) == .openTab(url: "chrome-extension://opt/settings.html"),
               "no popup: the options page in a tab")
        expect(ExtensionLaunch.decide("bare", available: all, hasPage: false) == .openTab(url: "chrome://extensions/?id=bare"),
               "neither: Chrome's details page for it")
    }

    /// The app's clock: work runs whether or not the caller keeps the handle, and only cancel()
    /// stops it. SharingService's first usage report, 30 s after launch, was dropped because its
    /// handle wasn't kept, so 0.1.38 sent no stats until six hours in.
    @MainActor
    private static func liveScheduler() {
        let clock = LiveScheduler()
        var dropped = false, kept = false, cancelled = false
        _ = clock.after(0.05) { dropped = true }
        let handle = clock.after(0.05) { kept = true }
        clock.after(0.05) { cancelled = true }.cancel()
        let until = Date().addingTimeInterval(2)
        while !(dropped && kept), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        expect(kept, "kept work runs")
        expect(dropped, "work whose handle was let go still runs")
        expect(!cancelled, "cancelled work doesn't run")
        _ = handle
    }

    private static func featureFlags() {
        expect(FeatureFlags(parsing: "").backdrop == .layer, "the calibrated backdrop layer is the default")
        expect(FeatureFlags(parsing: "backdrop=material").backdrop == .material, "CRA_FLAGS picks the material path")
        expect(FeatureFlags(parsing: "x=1&backdrop=material&y").backdrop == .material, "other keys around it are ignored")
        expect(FeatureFlags(parsing: "backdrop=glass").backdrop == .layer && FeatureFlags(parsing: "backdrop").backdrop == .layer,
               "an unknown value or a bare key keeps the default")
        expect(FeatureFlags(parsing: "backdrop=material").summary == "backdrop=material", "the log line names the path")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
