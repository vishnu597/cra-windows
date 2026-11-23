import CraCEFWin
import CraCore
import Foundation
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

/// A pane's XAML and how to put its controls in step with the settings again.
@MainActor
struct SettingsPaneContent {
    let element: UIElement
    let sync: () -> Void
}

/// The panes the Windows app has so far (DiaSettingsPane.windowsPanes), with the Mac's wording.
/// Rows wait for their feature.
@MainActor
enum SettingsPanes {
    // MARK: General

    /// Dia's card idiom (GeneralPane on the Mac): a "System" card with Cra's place in Windows.
    /// `importData` opens Import from Another Browser in the browser window in use (the Mac's
    /// Advanced ▸ Your data row; Windows' Advanced pane has only how Cra opens).
    static func general(store: SidebarStore, palette: SettingsPalette, importData: @escaping @MainActor () -> Void,
                        exportSpaces: @escaping @MainActor () -> Void) -> SettingsPaneContent {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.margin = Thickness(left: Double(DiaSettingsMetrics.paneInset), top: Double(DiaSettingsMetrics.paneTop),
                                 right: Double(DiaSettingsMetrics.paneInset), bottom: 20)
        stack.children.append(header("System", palette: palette))

        let footnote = UI.text("", size: 11, color: palette.error, trimmed: false)
        footnote.textWrapping = .wrap
        footnote.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 6, right: 0, bottom: 0)
        footnote.visibility = .collapsed

        let toggle = ToggleSwitch()
        toggle.onContent = ""
        toggle.offContent = ""
        toggle.minWidth = 0
        toggle.isOn = LaunchAtLogin.isEnabled
        toggle.toggled.addHandler { [weak toggle] _, _ in
            guard let toggle else { return }
            let want = toggle.isOn
            guard want != LaunchAtLogin.isEnabled else { return }
            let error = LaunchAtLogin.set(want)
            footnote.text = error ?? ""
            footnote.visibility = error == nil ? .collapsed : .visible
            // Back to what Windows has (toggled again, which then finds nothing to do).
            if error != nil { toggle.isOn = LaunchAtLogin.isEnabled }
        }
        try? AutomationProperties.setName(toggle, "Open Cra at login")

        // "Default browser": Cra with a check, or the browser links open in now and the button.
        let isCra = StackPanel()
        isCra.orientation = .horizontal
        isCra.spacing = 6
        let check = FontIcon()
        check.glyph = "\u{E930}"
        check.fontSize = 14
        check.foreground = palette.secondaryText
        check.verticalAlignment = .center
        isCra.children.append(check)
        isCra.children.append(UI.text("Cra", color: palette.secondaryText))
        let current = UI.text("", color: palette.secondaryText)
        current.verticalAlignment = .center
        let hint = note("Cra works best as your default browser.", palette: palette)
        hint.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 6, right: 0, bottom: 0)
        var setDefaultButton: Button?
        func syncBrowser() -> Bool {
            let isDefault = DefaultBrowser.isDefault
            isCra.visibility = isDefault ? .visible : .collapsed
            setDefaultButton?.visibility = isDefault ? .collapsed : .visible
            current.text = isDefault ? "" : DefaultBrowser.currentName ?? ""
            current.visibility = current.text.isEmpty ? .collapsed : .visible
            hint.visibility = isDefault ? .collapsed : .visible
            return isDefault
        }
        // Windows asks in its own Settings app: the row follows its answer for two minutes.
        let clock = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()).map { WinScheduler(queue: $0) }
        var watch: ScheduledWork?
        let setDefault = UI.button("Set Cra as Default") {
            guard DefaultBrowser.makeDefault() else {
                footnote.text = "Cra could not be registered as a browser."
                footnote.visibility = .visible
                return
            }
            footnote.visibility = .collapsed
            watch?.cancel()
            var ticks = 0
            watch = clock?.every(2) {
                ticks += 1
                if syncBrowser() || ticks >= 60 { watch?.cancel() }
            }
        }
        let browser = StackPanel()
        browser.orientation = .horizontal
        browser.spacing = 10
        browser.children.append(isCra)
        browser.children.append(current)
        browser.children.append(setDefault)
        setDefaultButton = setDefault
        _ = syncBrowser()

        // The Mac's General ▸ Warn before quitting: on Windows, closing the last window quits.
        var syncs: [() -> Void] = []
        let warn = settingSwitch("Warn before quitting", detail: "Closing the last window asks “Quit Cra?” first.",
                                 \.warnBeforeQuitting, store: store, palette: palette, syncs: &syncs)
        stack.children.append(card([cardRow("Default browser", trailing: browser, palette: palette),
                                    cardRow("Open Cra at login", trailing: toggle, palette: palette), warn], palette: palette))
        stack.children.append(hint)
        stack.children.append(footnote)

        let data = header("Your data", palette: palette)
        data.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(data)
        stack.children.append(card([
            cardRow("Import from another browser", trailing: UI.button("Import…") { importData() }, palette: palette),
            // The Mac's Advanced ▸ Your data row (SidebarExport).
            cardRow("Export spaces and pinned tabs",
                    detail: "Save every space’s favorites, pinned tabs and folders as a bookmarks file that Chrome, Edge, Firefox and other browsers can import.",
                    trailing: UI.button("Export…") { exportSpaces() }, palette: palette),
        ], palette: palette))

        // Arc's Icon tab (the Mac's IconPane, #372): Cra's four icons, the picked one ringed.
        let iconHeader = header("App icon", palette: palette)
        iconHeader.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(iconHeader)
        stack.children.append(appIconCard(palette: palette, syncs: &syncs))
        let iconNote = note("Cra’s windows, their taskbar buttons and Alt+Tab show it at once. A taskbar pin and the Start menu keep Segments.",
                            palette: palette)
        iconNote.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 6, right: 0, bottom: 0)
        stack.children.append(iconNote)
        // Task Manager can turn it off while the window is open, Windows' Settings change the
        // default browser.
        return SettingsPaneContent(element: stack) {
            let on = LaunchAtLogin.isEnabled
            if toggle.isOn != on { toggle.isOn = on }
            _ = syncBrowser()
            syncs.forEach { $0() }
        }
    }

    /// A tile for each of `AppIconChoice.presets`: its 64 DIP picture in a ring (the accent once
    /// picked), its name under it; a click picks it (`WindowIcon.select`).
    private static func appIconCard(palette: SettingsPalette, syncs: inout [() -> Void]) -> UIElement {
        let row = StackPanel()
        row.orientation = .horizontal
        row.spacing = 18
        row.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 14, right: 14, bottom: 12)
        func paint(_ ring: Border, _ label: TextBlock, picked: Bool) {
            if picked { ring.borderBrush = palette.accent } else { ring.borderBrush = UI.clear }
            label.fontWeight = UWP.FontWeight(weight: picked ? 600 : 400)
        }
        var rings: [(String, Border, TextBlock)] = []
        for option in AppIconChoice.presets {
            let tile = StackPanel()
            tile.orientation = .vertical
            tile.spacing = 6
            tile.background = UI.clear
            let ring = Border()
            ring.width = 76
            ring.height = 76
            ring.cornerRadius = CornerRadius(topLeft: 18, topRight: 18, bottomRight: 18, bottomLeft: 18)
            ring.borderThickness = Thickness(left: 2, top: 2, right: 2, bottom: 2)
            ring.padding = Thickness(left: 4, top: 4, right: 4, bottom: 4)
            if let file = WindowIcon.pictureFile(option.id), let data = try? Data(contentsOf: file),
               let bitmap = Pixels.decode(data, side: 128)?.bitmap() {
                ring.child = UI.image(bitmap, size: 64)
            }
            tile.children.append(ring)
            let name = UI.text(option.name, size: 12, color: palette.text)
            name.horizontalAlignment = .center
            tile.children.append(name)
            try? AutomationProperties.setName(tile, "\(option.name) app icon")
            let id = option.id
            tile.tapped.addHandler { _, _ in
                guard WindowIcon.selectedID != id else { return }
                WindowIcon.select(id)
                for (other, ring, label) in rings { paint(ring, label, picked: other == id) }
            }
            row.children.append(tile)
            rings.append((id, ring, name))
        }
        let shown = rings
        let sync = { for (id, ring, label) in shown { paint(ring, label, picked: id == WindowIcon.selectedID) } }
        sync()
        syncs.append(sync)
        return card([row], palette: palette)
    }

    // MARK: Privacy

    /// Dia's "Content blocking" card (PrivacyPane on the Mac), with the switches Windows has so
    /// far: the ad and tracker blocker and cookie banners. Fingerprinting, secure connections
    /// and the Data card wait for their features.
    /// `openURL` opens a page in the browser window in use (Clear browsing data's Chrome dialog).
    static func privacy(store: SidebarStore, palette: SettingsPalette, owner: @escaping @MainActor () -> UInt = { 0 },
                        openURL: @escaping @MainActor (String) -> Void) -> SettingsPaneContent {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.margin = Thickness(left: Double(DiaSettingsMetrics.paneInset), top: Double(DiaSettingsMetrics.paneTop),
                                 right: Double(DiaSettingsMetrics.paneInset), bottom: 20)
        stack.children.append(header("Content blocking", palette: palette))
        var syncs: [() -> Void] = []
        func switchRow(_ title: String, detail: String, _ key: WritableKeyPath<AppSettings, Bool>) -> Grid {
            settingSwitch(title, detail: detail, key, store: store, palette: palette, syncs: &syncs)
        }
        stack.children.append(card([
            switchRow("Block ads and trackers",
                      detail: "Requests to known ad and tracker domains are cancelled, unless the domain belongs to the site you’re on.",
                      \.blockAdsAndTrackers),
            blockLists(store: store, palette: palette, owner: owner, syncs: &syncs),
            // Arc: Settings ▸ General "Block Cookie Banners", off by default.
            switchRow("Block cookie banners",
                      detail: "Cookie banners from the common consent tools are hidden. Pages load again with the change.",
                      \.blockCookieBanners),
        ], palette: palette))
        let connections = header("Connections", palette: palette)
        connections.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(connections)
        // Secure DNS is Chromium's, in Local State: read again each time the pane shows.
        let dns = SecureDNSRows(palette: palette)
        syncs.append { dns.refresh() }
        stack.children.append(card([
            switchRow("Always use secure connections",
                      detail: "Pages load over HTTPS. Before opening a site that doesn’t support it, Cra warns you first.",
                      \.httpsOnly),
            dns.element,
        ], palette: palette))
        let data = header("Data", palette: palette)
        data.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(data)
        stack.children.append(card([
            cardRow("Clear browsing data",
                    detail: "Delete history, cookies and cached files for the current space’s profile. History you delete also leaves the command bar.",
                    trailing: UI.button("Clear…") { openURL(BrowsingDataClear.pageURL) }, palette: palette),
        ], palette: palette))
        // The Site Control Center's switch and the onboarding change them too.
        return SettingsPaneContent(element: stack) { syncs.forEach { $0() } }
    }

    /// Block lists added on top of Cra's own (#507, the Mac's BlockListRows): Add List… asks for
    /// an address or a file, and each list is a line with its name, what it blocks or why it
    /// couldn't be fetched, Try Again and Remove. Its lines follow WinBlockLists as it fetches.
    static func blockLists(store: SidebarStore, palette: SettingsPalette, owner: @escaping @MainActor () -> UInt,
                           syncs: inout [() -> Void]) -> UIElement {
        let lists = WinBlockLists.shared
        let section = StackPanel()
        section.orientation = .vertical

        let add = Button()
        add.content = UI.text("Add List…", trimmed: false)
        let flyout = Flyout()
        let field = TextBox()
        field.placeholderText = "https://example.com/list.txt"
        field.minWidth = 300
        try? AutomationProperties.setName(field, "List address")
        let error = UI.text("", size: 11, color: palette.secondaryText, trimmed: false)
        error.textWrapping = .wrap
        error.maxWidth = 300
        error.visibility = .collapsed
        // Strong, as `field` below: a WinRT control built from Swift is only a wrapper, gone
        // once nothing in Swift holds it, so a weak capture was nil by the time Add or Return
        // ran and the typed address was dropped (PC test, 22 Nov 2026). The cycle through the
        // handlers keeps one flyout and field per Privacy pane alive, which is the point.
        let shown: Flyout? = flyout
        func apply(_ addition: CustomBlocklist.Addition) {
            switch addition {
            case .invalid:
                error.text = BlocklistRow.invalidAddress
                error.visibility = .visible
                return
            case .added(let next):
                store.settings.customBlocklists = next
            case .alreadyAdded:
                break
            }
            try? shown?.hide()
        }
        let addTyped = {
            apply(CustomBlocklist.adding(field.text, to: store.settings.customBlocklists, httpsOnly: false))
        }
        field.keyDown.addHandler { _, args in
            guard let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x0D else { return }
            args.handled = true
            addTyped()
        }
        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.horizontalAlignment = .right
        let choose = Button()
        choose.content = UI.text("Choose File…", trimmed: false)
        choose.click.addHandler { _, _ in
            try? shown?.hide()
            guard let file = WinShell.pickFile(owner: owner(), title: "Choose a block list: a hosts file, a list of domains or an Adblock Plus list") else { return }
            apply(CustomBlocklist.adding(file, to: store.settings.customBlocklists))
        }
        let confirm = Button()
        confirm.content = UI.text("Add", trimmed: false)
        confirm.click.addHandler { _, _ in addTyped() }
        buttons.children.append(choose)
        buttons.children.append(confirm)
        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 8
        panel.children.append(UI.text("Add a Block List", color: palette.text))
        panel.children.append(field)
        panel.children.append(error)
        panel.children.append(buttons)
        flyout.content = panel
        flyout.opened.addHandler { _, _ in
            field.text = ""
            error.visibility = .collapsed
        }
        add.flyout = flyout
        section.children.append(cardRow("Block lists", detail: BlocklistRow.detail, trailing: add, palette: palette))

        // One line per list, built again whenever the lists or their fetches change.
        let rows = StackPanel()
        rows.orientation = .vertical
        rows.spacing = 6
        rows.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 0, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 10)
        section.children.append(rows)
        func render() {
            let enabled = store.settings.blockAdsAndTrackers
            add.isEnabled = enabled
            rows.opacity = enabled ? 1 : 0.5
            rows.children.clear()
            let addresses = store.settings.customBlocklists
            rows.visibility = addresses.isEmpty ? .collapsed : .visible
            for address in addresses {
                let line = Grid()
                line.columnDefinitions.append(UI.column(UI.star))
                line.columnDefinitions.append(UI.column(UI.auto))
                let words = StackPanel()
                words.spacing = 1
                words.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
                let cached = lists.cached[address]
                let name = BlocklistRow.name(address, cached: cached)
                words.children.append(UI.text(name, size: 12, color: palette.text, trimmed: true))
                let actions = StackPanel()
                actions.orientation = .horizontal
                actions.spacing = 4
                actions.verticalAlignment = .center
                let status: String
                switch BlocklistRow.status(cached: cached, failure: lists.failures[address], now: Date()) {
                case .fetching: status = "Fetching…"
                case .fetched(let text): status = lists.fetching.contains(address) ? text + " · Fetching…" : text
                case .failed(let why):
                    status = why
                    if !lists.fetching.contains(address) {
                        actions.children.append(UI.button("Try Again", color: palette.text) { lists.fetch(address) })
                    }
                }
                let detail = UI.text(status, size: 11, color: palette.secondaryText, trimmed: false)
                detail.textWrapping = .wrap
                words.children.append(detail)
                let remove = UI.button("Remove", color: palette.text) {
                    store.settings.customBlocklists.removeAll { $0 == address }
                }
                try? AutomationProperties.setName(remove, "Remove \(name)")
                actions.children.append(remove)
                line.children.append(words)
                line.children.append(actions)
                try? Grid.setColumn(actions, 1)
                rows.children.append(line)
            }
        }
        render()
        // Reading WinBlockLists here is what lets the pane follow a fetch as it finishes.
        syncs.append { render() }
        return section
    }

    /// A card row with a switch for one of the store's settings; `syncs` gets what puts the
    /// switch back in step when the setting changes elsewhere.
    static func settingSwitch(_ title: String, detail: String?, _ key: WritableKeyPath<AppSettings, Bool>,
                              store: SidebarStore, palette: SettingsPalette, syncs: inout [() -> Void]) -> Grid {
        let toggle = ToggleSwitch()
        toggle.onContent = ""
        toggle.offContent = ""
        toggle.minWidth = 0
        toggle.isOn = store.settings[keyPath: key]
        toggle.toggled.addHandler { [weak toggle] _, _ in
            guard let toggle else { return }
            let on = toggle.isOn
            if store.settings[keyPath: key] != on { store.settings[keyPath: key] = on }
        }
        try? AutomationProperties.setName(toggle, title)
        syncs.append {
            let on = store.settings[keyPath: key]
            if toggle.isOn != on { toggle.isOn = on }
        }
        return cardRow(title, detail: detail, trailing: toggle, palette: palette)
    }

    // MARK: Advanced

    /// The Mac's AdvancedPane, as far as Windows has its features: how Cra opens, and dragging the
    /// window from a page's top.
    static func advanced(store: SidebarStore, palette: SettingsPalette) -> SettingsPaneContent {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.margin = Thickness(left: Double(DiaSettingsMetrics.paneInset), top: Double(DiaSettingsMetrics.paneTop),
                                 right: Double(DiaSettingsMetrics.paneInset), bottom: 20)
        var syncs: [() -> Void] = []
        // The search engine and its suggestions are in Profiles, where Arc has them.
        for part in commandBarSection(store: store, palette: palette, syncs: &syncs) { stack.children.append(part) }
        let opening = header("Opening and quitting", palette: palette)
        opening.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(opening)
        stack.children.append(card([
            // Arc's Advanced switch: off, only the window in use last comes back.
            settingSwitch("When opening Cra, restore windows from previous session", detail: nil, \.restoreWindows,
                          store: store, palette: palette, syncs: &syncs),
            // Arc's: a press near a page's top moves the window, as from the title bar.
            settingSwitch("Allow window dragging from the top of webpages", detail: nil, \.pageTopWindowDrag,
                          store: store, palette: palette, syncs: &syncs),
            // Not in Arc (X DM 7 Nov 2026): Arc opens on the tab in use last.
            settingSwitch("Start on a new tab",
                          detail: "When Cra opens, it starts on a new tab instead of the tab you used last.", \.startOnNewTab,
                          store: store, palette: palette, syncs: &syncs),
            // The Mac's "Keep Cra in the menu bar" (#231, not in Arc): on Windows, closing the last window is the quit.
            settingSwitch("Keep Cra in the notification area",
                          detail: "Closing the last window keeps Cra running behind its icon by the clock, so a window or Little Window opens at once. Quit Cra from the icon’s menu.",
                          \.keepInMenuBar, store: store, palette: palette, syncs: &syncs),
        ], palette: palette))
        // Arc's Advanced tile: the video of a tab left goes on playing in Picture in Picture.
        let media = header("Media", palette: palette)
        media.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(media)
        stack.children.append(card([
            settingSwitch("Enable Picture in Picture when you leave a video tab", detail: nil, \.autoPictureInPicture,
                          store: store, palette: palette, syncs: &syncs),
        ], palette: palette))
        // The Mac's About card: the version (a click copies it with the engine, for a bug report,
        // #461), the engine and where Cra keeps its data.
        let about = header("About", palette: palette)
        about.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(about)
        stack.children.append(aboutCard(palette: palette))
        return SettingsPaneContent(element: stack) { syncs.forEach { $0() } }
    }

    private static func aboutCard(palette: SettingsPalette) -> FrameworkElement {
        let version = WinShell.appVersion
        let engine = EngineVersion.label(chromium: String(cString: cra_cef_chromium_version()), cef: String(cString: cra_cef_version()))
        let title = CraVersion.windowsTitle(version: version)
        let lines = StackPanel()
        lines.orientation = .vertical
        lines.spacing = 3
        lines.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 12, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 12)
        let label = UI.text(title, color: palette.text, trimmed: false)
        label.fontWeight = UWP.FontWeight(weight: 600)
        label.fontSize = 14
        let copy = Button()
        copy.content = label
        copy.background = UI.clear
        copy.borderThickness = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        copy.padding = Thickness(left: 0, top: 0, right: 0, bottom: 0)
        try? ToolTipService.setToolTip(copy, "Copy the Cra version")
        try? AutomationProperties.setName(copy, "Copy the Cra version")
        copy.click.addHandler { [weak label] _, _ in
            guard WinShell.copy(CraVersion.windowsLine(version: version, engine: engine)) else { return }
            // Settings has no toast: the title says so for a moment.
            label?.text = "Cra version copied to clipboard"
            try? aboutTimer?.stop()
            guard let queue = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil,
                  let timer = try? queue.createTimer() else { return }
            timer.interval = TimeSpan(duration: 2 * 10_000_000)
            timer.isRepeating = false
            timer.tick.addHandler { [weak label] _, _ in label?.text = title }
            try? timer.start()
            aboutTimer = timer
        }
        lines.children.append(copy)
        lines.children.append(UI.text(engine, size: 12, color: palette.secondaryText, trimmed: false))
        let folder = UI.text(WinPaths.native(WinPaths.supportDir), size: 11, color: palette.secondaryText, trimmed: false)
        lines.children.append(folder)
        return card([lines], palette: palette)
    }

    /// Puts the About title back after "copied", kept until it fires.
    private static var aboutTimer: WinAppSDK.DispatcherQueueTimer?

    /// The Mac's SidebarExport.run: asks where to save CraCore's bookmarks file, writes it and
    /// shows it in Explorer. `owner` is the window the Save dialog opens over.
    static func exportSpaces(store: SidebarStore, owner: UInt) {
        let now = Date()
        guard let path = WinShell.save(owner: owner, title: "Export Spaces", fileName: BookmarksExport.fileName(at: now),
                                       typeName: "Bookmarks file", fileExtension: "html") else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        do {
            try BookmarksExport.html(store, exportedOn: formatter.string(from: now))
                .write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            Shell.showInFolder(path)
        } catch {
            print("Cra: exporting spaces failed: \(error)")
        }
    }

    // MARK: Tabs

    /// Dia's two-column form (TabsPane on the Mac): a label per group, checkboxes beside it.
    /// `keepActiveSites` opens the Always Keep Sites Active sheet from its button. Little Window,
    /// Peek and Air Traffic Control moved to Links.
    static func tabs(store: SidebarStore, palette: SettingsPalette, keepActiveSites: @escaping @MainActor (Button) -> Void) -> SettingsPaneContent {
        var syncs: [() -> Void] = []
        func checkbox(_ title: String, get: @escaping @MainActor () -> Bool, set: @escaping @MainActor (Bool) -> Void) -> CheckBox {
            let box = CheckBox()
            let label = UI.text(title, trimmed: false)
            label.textWrapping = .wrap
            box.content = label
            box.isChecked = get()
            box.click.addHandler { [weak box] _, _ in
                guard let box else { return }
                let on = box.isChecked == true
                if get() != on { set(on) }
            }
            syncs.append {
                let on = get()
                if box.isChecked != on { box.isChecked = on }
            }
            return box
        }
        func checkbox(_ title: String, _ key: WritableKeyPath<AppSettings, Bool>) -> CheckBox {
            checkbox(title, get: { store.settings[keyPath: key] }, set: { store.settings[keyPath: key] = $0 })
        }

        let form = Form(palette: palette)
        form.group("General:", [
            checkbox("Add new tabs to the top", \.newTabsAtTop),
            checkbox("Show the New Tab button above tabs", \.newTabButtonAtTop),
            // GitHub #601, not in Arc: Arc's Restore Last Closed Tab switches to the space of the
            // tab closed last.
            checkbox("Reopen tabs from this Space only", \.reopenClosedTabCurrentSpaceOnly),
            note("Restore Last Closed Tab (Ctrl+Shift+T) brings back the tab you closed last in the Space you’re in, instead of switching to another Space.", palette: palette),
        ])
        // Arc's single-space mode ("Hide Space Header" on the space's menu), for people who
        // don't use spaces.
        form.group("Spaces:", [
            checkbox("Show the space header with only one space", \.showSpaceHeaderOnSingleSpace),
            note("Off hides the space’s name and its icon at the bottom of the sidebar while you have one space.", palette: palette),
        ])
        // #305: Arc's View ▸ Show Toolbar, named for what it moves (AddressBarPlacement), and Arc's
        // Show Full URL from the toolbar address's menu (Settings ▸ Advanced on the Mac).
        form.group("Address bar:", [
            checkbox("Show the address in a toolbar above the page", get: { store.settings.addressBarPlacement == .toolbar },
                     set: { store.settings.addressBarPlacement = $0 ? .toolbar : .sidebar }),
            checkbox("Show the full URL in the toolbar", \.toolbarShowsFullURL),
            // Not in Arc (Zen's compact mode): the toolbar floats over the page's top until wanted.
            checkbox("Hide the toolbar until the pointer reaches the top of the page", \.autoHideToolbar),
            note("Off keeps the address at the top of the sidebar, as in Arc. Toggle Toolbar in the command bar switches it too.", palette: palette),
        ])
        // GitHub #464, not in Arc: the window's layout in a mirror (SidebarSide), as on the Mac.
        form.group("Sidebar:", [
            checkbox("Sidebar on the right", get: { store.settings.sidebarSide == .right },
                     set: { store.settings.sidebarSide = $0 ? .right : .left }),
            note("The sidebar sits on the right of the window. Hidden, it slides in from the right edge.", palette: palette),
        ])
        // #154: Arc's favorites, one set per profile (the Mac's "Tabs and Favorites" card).
        form.group("Favorites:", [
            checkbox("Share Favorites across Spaces", get: { store.settings.sharedFavorites }, set: { store.setFavoritesShared($0) }),
            note("Spaces on the same profile show the same Favorites, as in Arc. Turning it on combines their Favorites; turning it off gives each Space its own copy.",
                 palette: palette),
        ])

        let cleanup = StackPanel()
        cleanup.orientation = .horizontal
        cleanup.spacing = 6
        cleanup.children.append(checkbox("Archive tabs I haven’t used in:", \.autoArchiveEnabled))
        let thresholds = AutoArchiveThreshold.allCases
        let duration = ComboBox()
        duration.verticalAlignment = .center
        for t in thresholds { duration.items.append(t.label) }
        duration.selectedIndex = Int32(thresholds.firstIndex(of: store.settings.autoArchive) ?? 0)
        duration.isEnabled = store.settings.autoArchiveEnabled
        duration.selectionChanged.addHandler { [weak duration] _, _ in
            guard let duration else { return }
            let i = Int(duration.selectedIndex)
            guard thresholds.indices.contains(i), store.settings.autoArchive != thresholds[i] else { return }
            store.settings.autoArchive = thresholds[i]
        }
        try? AutomationProperties.setName(duration, "Archive tabs after")
        syncs.append {
            let i = Int32(thresholds.firstIndex(of: store.settings.autoArchive) ?? 0)
            if duration.selectedIndex != i { duration.selectedIndex = i }
            duration.isEnabled = store.settings.autoArchiveEnabled
        }
        cleanup.children.append(duration)
        form.group("Tab Cleanup:", [cleanup])
        // Tab sleeping (GitHub #153): Arc's 4 hours and nothing more unless you ask.
        let memory = StackPanel()
        memory.orientation = .horizontal
        memory.spacing = 6
        memory.children.append(checkbox("Free memory from tabs I haven’t used in:", \.tabSleepTimerEnabled))
        let sleepAfter = TabSleepThreshold.allCases
        let sleepDuration = ComboBox()
        sleepDuration.verticalAlignment = .center
        for t in sleepAfter { sleepDuration.items.append(t.label) }
        sleepDuration.selectedIndex = Int32(sleepAfter.firstIndex(of: store.settings.tabSleepAfter) ?? 0)
        sleepDuration.isEnabled = store.settings.tabSleepTimerEnabled
        sleepDuration.selectionChanged.addHandler { [weak sleepDuration] _, _ in
            guard let sleepDuration else { return }
            let i = Int(sleepDuration.selectedIndex)
            guard sleepAfter.indices.contains(i), store.settings.tabSleepAfter != sleepAfter[i] else { return }
            store.settings.tabSleepAfter = sleepAfter[i]
        }
        try? AutomationProperties.setName(sleepDuration, "Free memory from tabs after")
        syncs.append {
            let i = Int32(sleepAfter.firstIndex(of: store.settings.tabSleepAfter) ?? 0)
            if sleepDuration.selectedIndex != i { sleepDuration.selectedIndex = i }
            sleepDuration.isEnabled = store.settings.tabSleepTimerEnabled
        }
        memory.children.append(sleepDuration)
        let sleepNote = note(TabSleepPolicy.settingsNote(timerOn: store.settings.tabSleepTimerEnabled, after: store.settings.tabSleepAfter),
                             palette: palette)
        syncs.append {
            sleepNote.text = TabSleepPolicy.settingsNote(timerOn: store.settings.tabSleepTimerEnabled, after: store.settings.tabSleepAfter)
        }
        // #458: Arc's (and Chrome's) list at arc://settings/performance.
        let keepRow = StackPanel()
        keepRow.orientation = .horizontal
        keepRow.spacing = 8
        keepRow.margin = Thickness(left: 0, top: 6, right: 0, bottom: 2)
        let sitesButton = Button()
        sitesButton.content = UI.text("Always Keep Sites Active…", trimmed: false)
        sitesButton.click.addHandler { [weak sitesButton] _, _ in
            if let sitesButton { keepActiveSites(sitesButton) }
        }
        keepRow.children.append(sitesButton)
        func keptSummary() -> String {
            switch store.settings.keepActiveSites.count {
            case 0: return "No sites"
            case 1: return "1 site"
            case let n: return "\(n) sites"
            }
        }
        let keptCount = UI.text(keptSummary(), size: 11, color: palette.secondaryText)
        keptCount.verticalAlignment = .center
        keepRow.children.append(keptCount)
        syncs.append { [sitesButton] in
            _ = sitesButton
            keptCount.text = keptSummary()
        }
        form.group("Memory:", [memory, sleepNote, keepRow])
        return SettingsPaneContent(element: form.grid) { for sync in syncs { sync() } }
    }

    // MARK: Links

    /// Arc's Links pane (LinksPane on the Mac, upstream b4c20de): Little Window, then Peek, each
    /// under its blurb, then "Choose where links open" with Air Traffic Control…, then Cra's New
    /// tabs card. Rows whose feature Windows doesn't have yet (the Little Window's ⌥⌘-click and
    /// archive time, Peek's ⌘-click Expand, hiding either toolbar, background tabs below the
    /// current one, Split View's) wait for it.
    static func links(store: SidebarStore, palette: SettingsPalette,
                      airTrafficControl: @escaping @MainActor (Button) -> Void) -> SettingsPaneContent {
        var syncs: [() -> Void] = []
        func checkbox(_ title: String, get: @escaping @MainActor () -> Bool, set: @escaping @MainActor (Bool) -> Void) -> CheckBox {
            let box = CheckBox()
            let label = UI.text(title, trimmed: false)
            label.textWrapping = .wrap
            box.content = label
            box.isChecked = get()
            box.click.addHandler { [weak box] _, _ in
                guard let box else { return }
                let on = box.isChecked == true
                if get() != on { set(on) }
            }
            syncs.append {
                let on = get()
                if box.isChecked != on { box.isChecked = on }
            }
            return box
        }
        func checkbox(_ title: String, _ key: WritableKeyPath<AppSettings, Bool>) -> CheckBox {
            checkbox(title, get: { store.settings[keyPath: key] }, set: { store.settings[keyPath: key] = $0 })
        }

        // Arc's line over each card, in the text colour and flush with the switches.
        func blurb(_ text: String) -> TextBlock {
            let t = UI.text(text, size: 12, color: palette.text, trimmed: false)
            t.textWrapping = .wrap
            t.margin = Thickness(left: 0, top: 0, right: 0, bottom: 4)
            return t
        }
        let form = Form(palette: palette)
        let littleKey = WinKeyBindings.shared.action("newLittleWindow")?.primary?.windowsDisplay ?? "Ctrl+Alt+N"
        form.group("Little Window:", [
            blurb("Little Window is a smaller, simpler window. It’s perfect for quick lookups and reading funny tweets your friends send you."),
            // Arc: "Open Little Arc when I press ⌥⌘N in any app" (#195).
            checkbox("Open Little Window when I press \(littleKey) in any app", \.littleWindowShortcutEverywhere),
            checkbox("Links from other apps open in Little Window", \.openExternalLinksInLittleWindow),
        ])
        let otherSitesNote = note("Note: This only affects Favorites and Pinned tabs", palette: palette)
        // Cra's addition (#12), under the switch it widens.
        let everyTab = checkbox("Peek at links to other sites in every tab", \.peekInEveryTab)
        everyTab.isEnabled = store.settings.peekLinksToOtherSites
        syncs.append { everyTab.isEnabled = store.settings.peekLinksToOtherSites }
        form.group("Peek:", [
            blurb("Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet."),
            checkbox("Open a Peek window when clicking on links with Shift held", \.peekOnShiftClick),
            checkbox("Open a Peek window when clicking on links to other sites", \.peekLinksToOtherSites),
            otherSitesNote,
            everyTab,
        ])

        let routesRow = StackPanel()
        routesRow.orientation = .horizontal
        routesRow.spacing = 8
        routesRow.margin = Thickness(left: 0, top: 2, right: 0, bottom: 2)
        let routesButton = Button()
        routesButton.content = UI.text("Air Traffic Control…", trimmed: false)
        routesButton.click.addHandler { [weak routesButton] _, _ in
            if let routesButton { airTrafficControl(routesButton) }
        }
        routesRow.children.append(routesButton)
        let summary = UI.text(AirTrafficControl.summary(routes: store.settings.linkRoutes.count), size: 11, color: palette.secondaryText)
        summary.verticalAlignment = .center
        routesRow.children.append(summary)
        // Also keeps the button's wrapper while the pane shows, for its handler's weak capture.
        syncs.append { [routesButton] in
            _ = routesButton
            summary.text = AirTrafficControl.summary(routes: store.settings.linkRoutes.count)
        }
        form.group("Air Traffic Control:", [
            blurb("Choose where links open inside Cra."),
            routesRow,
            note(AirTrafficControl.settingsNote, palette: palette),
        ])
        // Not in Arc's tab: what the page menu's "Open Link in New Tab" does (#276).
        form.group("New tabs:", [
            checkbox("Switch to links opened in new tabs", \.openLinksInForeground),
            note("“Open Link in New Tab” brings the new tab to the front. Off, the page you’re reading stays in front, as in Arc. Ctrl-click opens a link behind the page and Ctrl+Shift-click switches to it either way.", palette: palette),
        ])

        return SettingsPaneContent(element: form.grid) { for sync in syncs { sync() } }
    }

    // MARK: Profiles

    /// Dia's Profiles pane (ProfilesPane on the Mac): Default and each profile with the spaces on
    /// it, Rename… and Delete… on a profile, Create Profile… under the card. Arc only deletes
    /// profiles no space uses, and never Default. `newProfile` opens Create a new Profile in the
    /// browser window in use.
    static func profiles(store: SidebarStore, palette: SettingsPalette, owner: @escaping @MainActor () -> UInt,
                         openProfilePage: @escaping @MainActor (String, UUID?) -> Void = { _, _ in },
                         presentDialog: @escaping @MainActor (AppDialog, @escaping (Int?) -> Void) -> Void,
                         newProfile: @escaping @MainActor () -> Void) -> SettingsPaneContent {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.margin = Thickness(left: Double(DiaSettingsMetrics.paneInset), top: Double(DiaSettingsMetrics.paneTop),
                                 right: Double(DiaSettingsMetrics.paneInset), bottom: 20)
        stack.children.append(header("Profiles", palette: palette))
        let holder = Border()
        stack.children.append(holder)

        let create = Button()
        create.content = UI.text("Create Profile…", trimmed: false)
        create.margin = Thickness(left: 0, top: 10, right: 0, bottom: 0)
        create.click.addHandler { _, _ in newProfile() }
        if ArcProfileRebuilder.isAvailable {
            // Spaces an Arc import left on Default, back on their Arc profiles (#131), as the Mac's
            // Default profile offers.
            let row = StackPanel()
            row.orientation = .horizontal
            row.spacing = 8
            row.children.append(create)
            let rebuild = Button()
            rebuild.content = UI.text("Rebuild from Arc…", trimmed: false)
            rebuild.margin = create.margin
            try? ToolTipService.setToolTip(rebuild, "Put spaces imported from Arc back on the profiles they use in Arc, with their sign-ins.")
            rebuild.click.addHandler { _, _ in ArcProfileRebuilder.run(store: store, present: presentDialog) }
            row.children.append(rebuild)
            stack.children.append(row)
        } else {
            stack.children.append(create)
        }
        let footnote = UI.text("Profiles help keep your data separate across Spaces, like logins, cookies and site data. You can use any Profile across one or more Spaces: choose Change Profile in the command bar, or Set Profile on a Space’s menu. Spaces on the same Profile share their logins. Only Profiles not assigned to any Spaces can be deleted.",
                               size: 11, color: palette.secondaryText, trimmed: false)
        footnote.textWrapping = .wrap
        footnote.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 10, right: 0, bottom: 0)
        stack.children.append(footnote)

        // Rebuilt when a profile, or which spaces use one, changes (not on every space edit, so an
        // open Rename flyout stays).
        var shown = ""
        // The rows' fields and flyouts, which their handlers capture weakly: a WinRT control built
        // from Swift is only a wrapper, gone once nothing in Swift holds it, however long XAML
        // keeps the control.
        var kept: [AnyObject] = []
        func rebuild() {
            let rows: [(String, BrowserProfile?, [Space])] = [(store.profileName(nil), nil, store.spaces(usingProfile: nil))]
                + store.profiles.map { ($0.name, $0, store.spaces(usingProfile: $0.id)) }
            let signature = rows.map { "\($0.1?.id.uuidString ?? "-")|\($0.0)|" + $0.2.map { "\($0.emoji)\($0.title)" }.joined(separator: ",") }
                .joined(separator: "\n") + "\n" + DownloadLocation.bridgeLines(store.settings.downloadLocations, profiles: store.profiles)
                // Chromium's language page changes them while the pane is away.
                + "\n" + rows.map { websiteLanguages(profileID: $0.1?.id, store: store).joined(separator: ",") }.joined(separator: "|")
            guard signature != shown else { return }
            shown = signature
            var parts: [AnyObject] = []
            holder.child = card(rows.map { name, profile, spaces in
                profileRow(name: name, profile: profile, spaces: spaces, store: store, palette: palette, owner: owner,
                           openProfilePage: openProfilePage, presentDialog: presentDialog) { parts.append($0) }
            }, palette: palette)
            kept = parts
        }
        rebuild()
        // Search, as the Mac's Profiles pane has it (the command bar notice's Search Settings… opens here).
        var searchSyncs: [() -> Void] = []
        let search = header("Search", palette: palette)
        search.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 20, right: 0, bottom: 8)
        stack.children.append(search)
        stack.children.append(searchCard(store: store, palette: palette, syncs: &searchSyncs))
        return SettingsPaneContent(element: stack) {
            rebuild()
            searchSyncs.forEach { $0() }
        }
    }

    /// A profile's website languages: Chromium's live value once it has loaded, else its
    /// Preferences file (`BrowserLanguages.codes(livePref:preferencesFile:)`).
    private static func websiteLanguages(profileID: UUID?, store: SidebarStore) -> [String] {
        let path = store.profilePath(profile: profileID)
        var live: String?
        if let json = cra_cef_preference_json(path, BrowserLanguages.pref) {
            live = String(cString: json)
            cra_data_free(json)
        }
        let folder = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? store.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        return BrowserLanguages.codes(livePref: live) { try? Data(contentsOf: folder.appendingPathComponent("Preferences")) }
    }

    private static func profileRow(name: String, profile: BrowserProfile?, spaces: [Space], store: SidebarStore,
                                   palette: SettingsPalette, owner: @escaping @MainActor () -> UInt,
                                   openProfilePage: @escaping @MainActor (String, UUID?) -> Void,
                                   presentDialog: @escaping @MainActor (AppDialog, @escaping (Int?) -> Void) -> Void,
                                   keep: (AnyObject) -> Void) -> Grid {
        let row = Grid()
        row.minHeight = Double(DiaSettingsMetrics.cardRowHeight) + 8
        row.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 6, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 6)
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        let labels = StackPanel()
        labels.orientation = .vertical
        labels.verticalAlignment = .center
        labels.children.append(UI.text(name, color: palette.text))
        let used = spaces.isEmpty ? "No Spaces" : spaces.map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")
        labels.children.append(UI.text(used, size: 11, color: palette.secondaryText))
        // Not in Arc's card: the website languages are Chromium's, per profile (#209, the Mac's
        // languageRow).
        let languages = BrowserLanguages.summary(websiteLanguages(profileID: profile?.id, store: store))
        let languagesLine = UI.text("Website languages: " + (languages.isEmpty ? "Chromium’s default languages" : languages),
                                    size: 11, color: palette.secondaryText, trimmed: false)
        languagesLine.textWrapping = .wrap
        labels.children.append(languagesLine)
        row.children.append(labels)

        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.verticalAlignment = .center
        row.children.append(buttons)
        try? Grid.setColumn(buttons, 1)
        buttons.children.append(downloadLocationButton(name: name, profileID: profile?.id, store: store, owner: owner, keep: keep))
        let languagesButton = Button()
        languagesButton.content = UI.text("Languages…", trimmed: false)
        languagesButton.isEnabled = !spaces.isEmpty
        try? AutomationProperties.setName(languagesButton, "Website languages for \(name)")
        try? ToolTipService.setToolTip(languagesButton, spaces.isEmpty ? "Set this Profile on a Space first."
                                                                  : "Open Chromium’s language settings for this Profile.")
        let profileID = profile?.id
        languagesButton.click.addHandler { _, _ in openProfilePage(BrowserLanguages.settingsPage, profileID) }
        buttons.children.append(languagesButton)
        // Rename…: Arc's sheet with the name in a field, Save waiting for one (the Mac's
        // ProfilesPane.rename, Default too).
        let rename = Button()
        rename.content = UI.text("Rename…", trimmed: false)
        try? AutomationProperties.setName(rename, "Rename “\(name)”…")
        let renamedID = profile?.id
        rename.click.addHandler { _, _ in
            let prompt = ProfilePrompts.rename(current: store.profileName(renamedID))
            let dialog = AppDialog(prompt, width: 496, buttonSpacing: 30, buttonOutset: 0)
            presentDialog(dialog) { [dialog] picked in
                guard picked == 0, let typed = prompt.accepted(dialog.input) else { return }
                store.renameProfile(renamedID, to: typed)
            }
        }
        buttons.children.append(rename)
        guard let profile else { return row }

        // Delete…: only a profile no space uses, after Arc's warning sheet.
        let delete = Button()
        delete.content = UI.text("Delete…", trimmed: false)
        delete.isEnabled = spaces.isEmpty
        try? AutomationProperties.setName(delete, "Delete “\(profile.name)”…")
        delete.click.addHandler { _, _ in
            let dialog = AppDialog(ProfilePrompts.delete(name: profile.name))
            presentDialog(dialog) { picked in
                if picked == 0 { store.deleteProfile(profile.id) }
            }
        }
        buttons.children.append(delete)
        return row
    }

    /// Arc's per-profile "Download location" pop-up (the Mac's ProfilesPane.downloadPicker): the
    /// folder, Other… for Windows' folder picker, and Ask Where to Save Each File.
    private static func downloadLocationButton(name: String, profileID: UUID?, store: SidebarStore,
                                               owner: @escaping @MainActor () -> UInt, keep: (AnyObject) -> Void) -> Button {
        let location = store.settings.downloadLocation(profileID: profileID)
        let button = Button()
        button.content = UI.text((location.askWhereToSave ? "Ask Each Time" : location.folderName) + "  ⌄", trimmed: false)
        try? AutomationProperties.setName(button, "Download location for \(name)")
        if let folder = location.folder { try? ToolTipService.setToolTip(button, folder) }
        let menu = MenuFlyout()
        func set(_ change: (inout DownloadLocation) -> Void) {
            var l = store.settings.downloadLocation(profileID: profileID)
            change(&l)
            store.settings.setDownloadLocation(l, profileID: profileID)
        }
        let folderItem = ToggleMenuFlyoutItem()
        folderItem.text = location.folderName
        folderItem.isChecked = !location.askWhereToSave
        folderItem.click.addHandler { _, _ in set { $0.askWhereToSave = false } }
        menu.items.append(folderItem)
        let other = MenuFlyoutItem()
        other.text = "Other…"
        other.click.addHandler { _, _ in
            guard let path = WinShell.pickFolderPath(owner: owner(), title: "Choose where \(name) saves downloaded files"),
                  DownloadLocation.isAbsolute(path) else { return }
            // Picking Downloads itself goes back to the default, as on the Mac.
            set { $0.folder = DownloadLocation.picked(path, downloads: WinShell.downloadsFolder); $0.askWhereToSave = false }
        }
        menu.items.append(other)
        menu.items.append(MenuFlyoutSeparator())
        let ask = ToggleMenuFlyoutItem()
        ask.text = "Ask Where to Save Each File"
        ask.isChecked = location.askWhereToSave
        ask.click.addHandler { _, _ in set { $0.askWhereToSave = true } }
        menu.items.append(ask)
        button.flyout = menu
        keep(menu)
        keep(button)
        return button
    }

    // MARK: Pieces

    /// Labels end 178.5 DIPs in and controls start at 202, as in Dia's form panes.
    @MainActor
    private final class Form {
        let grid = Grid()
        private let palette: SettingsPalette
        private var rows: Int32 = 0

        init(palette: SettingsPalette) {
            self.palette = palette
            grid.margin = Thickness(left: 0, top: Double(DiaSettingsMetrics.formTop), right: Double(DiaSettingsMetrics.paneInset), bottom: 20)
            grid.rowSpacing = Double(DiaSettingsMetrics.formGroupSpacing)
            grid.columnDefinitions.append(UI.column(UI.pixels(Double(DiaSettingsMetrics.formLabelWidth))))
            grid.columnDefinitions.append(UI.column(UI.pixels(Double(DiaSettingsMetrics.formControlX - DiaSettingsMetrics.formLabelWidth))))
            grid.columnDefinitions.append(UI.column(UI.star))
        }

        func group(_ label: String, _ controls: [UIElement]) {
            grid.rowDefinitions.append(UI.row(UI.auto))
            let title = UI.text(label, color: palette.text, trimmed: false)
            title.horizontalAlignment = .right
            title.verticalAlignment = .top
            // On the first checkbox's text line (a CheckBox is 32 DIPs tall).
            title.margin = Thickness(left: 0, top: 6, right: 0, bottom: 0)
            grid.children.append(title)
            try? Grid.setRow(title, rows)
            let stack = StackPanel()
            stack.orientation = .vertical
            for control in controls { stack.children.append(control) }
            grid.children.append(stack)
            try? Grid.setRow(stack, rows)
            try? Grid.setColumn(stack, 2)
            rows += 1
        }
    }

    static func header(_ title: String, palette: SettingsPalette) -> TextBlock {
        let t = UI.text(title, size: 13, color: palette.text, trimmed: false)
        t.fontWeight = UWP.FontWeight(weight: 600)
        t.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 0, right: 0, bottom: 8)
        return t
    }

    static func note(_ text: String, palette: SettingsPalette) -> TextBlock {
        let t = UI.text(text, size: 11, color: palette.secondaryText, trimmed: false)
        t.textWrapping = .wrap
        t.margin = Thickness(left: 28, top: 0, right: 0, bottom: 0)
        return t
    }

    /// Rounded card behind grouped rows, with a hairline between them.
    static func card(_ rows: [UIElement], palette: SettingsPalette) -> Border {
        let stack = StackPanel()
        stack.orientation = .vertical
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let line = Border()
                line.height = 1
                line.background = palette.hairline
                line.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 0, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 0)
                stack.children.append(line)
            }
            stack.children.append(row)
        }
        let border = Border()
        let corner = Double(DiaSettingsMetrics.cardCorner)
        border.cornerRadius = CornerRadius(topLeft: corner, topRight: corner, bottomRight: corner, bottomLeft: corner)
        border.background = palette.card
        border.child = stack
        return border
    }

    /// Label on the left, control on the right, 43 DIPs tall. A `detail` goes under the label
    /// in secondary text (the Mac's SettingsToggleRow), and the row grows to fit it.
    static func cardRow(_ title: String, detail: String? = nil, trailing: FrameworkElement, palette: SettingsPalette) -> Grid {
        let row = Grid()
        row.minHeight = Double(DiaSettingsMetrics.cardRowHeight)
        let pad = detail == nil ? 0.0 : 10.0
        row.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: pad, right: Double(DiaSettingsMetrics.cardRowInset), bottom: pad)
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        let label = UI.text(title, color: palette.text)
        if let detail {
            let words = StackPanel()
            words.spacing = 2
            words.verticalAlignment = .center
            words.margin = Thickness(left: 0, top: 0, right: 16, bottom: 0)
            words.children.append(label)
            let more = UI.text(detail, size: 11, color: palette.secondaryText, trimmed: false)
            more.textWrapping = .wrap
            words.children.append(more)
            row.children.append(words)
        } else {
            label.verticalAlignment = .center
            row.children.append(label)
        }
        trailing.verticalAlignment = .center
        row.children.append(trailing)
        try? Grid.setColumn(trailing, 1)
        return row
    }
}
