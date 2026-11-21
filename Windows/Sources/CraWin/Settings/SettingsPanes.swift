import CraCore
import Foundation
import UWP
import WinAppSDK
import WinUI

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
    static func general(palette: SettingsPalette, importData: @escaping @MainActor () -> Void,
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

        stack.children.append(card([cardRow("Default browser", trailing: browser, palette: palette),
                                    cardRow("Open Cra at login", trailing: toggle, palette: palette)], palette: palette))
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
        // Task Manager can turn it off while the window is open, Windows' Settings change the
        // default browser.
        return SettingsPaneContent(element: stack) {
            let on = LaunchAtLogin.isEnabled
            if toggle.isOn != on { toggle.isOn = on }
            _ = syncBrowser()
        }
    }

    // MARK: Privacy

    /// Dia's "Content blocking" card (PrivacyPane on the Mac), with the switches Windows has so
    /// far: the ad and tracker blocker and cookie banners. Fingerprinting, secure connections
    /// and the Data card wait for their features.
    /// `openURL` opens a page in the browser window in use (Clear browsing data's Chrome dialog).
    static func privacy(store: SidebarStore, palette: SettingsPalette,
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
        stack.children.append(header("Opening and quitting", palette: palette))
        var syncs: [() -> Void] = []
        stack.children.append(card([
            // Arc's Advanced switch: off, only the window in use last comes back.
            settingSwitch("When opening Cra, restore windows from previous session", detail: nil, \.restoreWindows,
                          store: store, palette: palette, syncs: &syncs),
            // The Mac's General ▸ Warn before quitting: closing the last window asks "Quit Cra?".
            settingSwitch("Warn before quitting", detail: "Closing the last window asks before Cra quits.", \.warnBeforeQuitting,
                          store: store, palette: palette, syncs: &syncs),
            // Arc's: a press near a page's top moves the window, as from the title bar.
            settingSwitch("Allow window dragging from the top of webpages", detail: nil, \.pageTopWindowDrag,
                          store: store, palette: palette, syncs: &syncs),
            // Not in Arc (X DM 7 Nov 2026): Arc opens on the tab in use last.
            settingSwitch("Start on a new tab",
                          detail: "When Cra opens, it starts on a new tab instead of the tab you used last.", \.startOnNewTab,
                          store: store, palette: palette, syncs: &syncs),
        ], palette: palette))
        return SettingsPaneContent(element: stack) { syncs.forEach { $0() } }
    }

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
    /// `airTrafficControl` opens the routes sheet from its button.
    static func tabs(store: SidebarStore, palette: SettingsPalette,
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
        form.group("Memory:", [memory, sleepNote])
        // Arc's Links pane: where links from other apps open, "Open Little Arc when I press ⌥⌘N"
        // (#195), New Little Window's key from any app, Peek's, and "Air Traffic Control…" with
        // how many routes there are.
        let routesRow = StackPanel()
        routesRow.orientation = .horizontal
        routesRow.spacing = 8
        routesRow.margin = Thickness(left: 0, top: 6, right: 0, bottom: 2)
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
        let routesNote = UI.text(AirTrafficControl.settingsNote, size: 11, color: palette.secondaryText, trimmed: false)
        routesNote.textWrapping = .wrap
        let littleKey = WinKeyBindings.shared.action("newLittleWindow")?.primary?.windowsDisplay ?? "Ctrl+Alt+N"
        let everyTab = checkbox("In every tab, not only Favorites and Pinned tabs", \.peekInEveryTab)
        everyTab.margin = Thickness(left: 20, top: 0, right: 0, bottom: 0)
        everyTab.isEnabled = store.settings.peekLinksToOtherSites
        syncs.append { everyTab.isEnabled = store.settings.peekLinksToOtherSites }
        form.group("Links:", [
            checkbox("Links from other apps open in a Little Window", \.openExternalLinksInLittleWindow),
            checkbox("Open a Little Window when I press \(littleKey) in any app", \.littleWindowShortcutEverywhere),
            checkbox("Open a Peek window when clicking on links to other sites", \.peekLinksToOtherSites),
            everyTab,
            checkbox("Open a Peek window when clicking on links with Shift held", \.peekOnShiftClick),
            // Not in Arc's tab: what the page menu's "Open Link in New Tab" does (#276).
            checkbox("Switch to links opened in new tabs from the page menu", \.openLinksInForeground),
            routesRow,
            routesNote,
        ])

        return SettingsPaneContent(element: form.grid) { for sync in syncs { sync() } }
    }

    // MARK: Profiles

    /// Dia's Profiles pane (ProfilesPane on the Mac): Default and each profile with the spaces on
    /// it, Rename… and Delete… on a profile, Create Profile… under the card. Arc only deletes
    /// profiles no space uses, and never Default. `newProfile` opens Create a new Profile in the
    /// browser window in use.
    static func profiles(store: SidebarStore, palette: SettingsPalette, owner: @escaping @MainActor () -> UInt,
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
        stack.children.append(create)
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
            let rows: [(String, BrowserProfile?, [Space])] = [("Default", nil, store.spaces(usingProfile: nil))]
                + store.profiles.map { ($0.name, $0, store.spaces(usingProfile: $0.id)) }
            let signature = rows.map { "\($0.1?.id.uuidString ?? "-")|\($0.0)|" + $0.2.map { "\($0.emoji)\($0.title)" }.joined(separator: ",") }
                .joined(separator: "\n") + "\n" + DownloadLocation.bridgeLines(store.settings.downloadLocations, profiles: store.profiles)
            guard signature != shown else { return }
            shown = signature
            var parts: [AnyObject] = []
            holder.child = card(rows.map { name, profile, spaces in
                profileRow(name: name, profile: profile, spaces: spaces, store: store, palette: palette, owner: owner) { parts.append($0) }
            }, palette: palette)
            kept = parts
        }
        rebuild()
        return SettingsPaneContent(element: stack) { rebuild() }
    }

    private static func profileRow(name: String, profile: BrowserProfile?, spaces: [Space], store: SidebarStore,
                                   palette: SettingsPalette, owner: @escaping @MainActor () -> UInt, keep: (AnyObject) -> Void) -> Grid {
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
        row.children.append(labels)

        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.verticalAlignment = .center
        row.children.append(buttons)
        try? Grid.setColumn(buttons, 1)
        buttons.children.append(downloadLocationButton(name: name, profileID: profile?.id, store: store, owner: owner, keep: keep))
        guard let profile else { return row }

        // Rename…: the name in a field under the button, Return or Rename to keep it.
        let rename = Button()
        rename.content = UI.text("Rename…", trimmed: false)
        let renameFlyout = Flyout()
        let field = TextBox()
        field.text = profile.name
        field.minWidth = 220
        try? AutomationProperties.setName(field, "Profile name")
        let apply = Button()
        apply.content = UI.text("Rename", trimmed: false)
        let commit = { [weak renameFlyout, weak field] in
            guard let field else { return }
            let name = field.text.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { store.renameProfile(profile.id, to: name) }
            try? renameFlyout?.hide()
        }
        apply.click.addHandler { _, _ in commit() }
        field.keyDown.addHandler { _, args in
            guard let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x0D else { return }
            args.handled = true
            commit()
        }
        let renamePanel = StackPanel()
        renamePanel.orientation = .vertical
        renamePanel.spacing = 8
        renamePanel.children.append(UI.text("Rename Profile", color: palette.text))
        renamePanel.children.append(field)
        apply.horizontalAlignment = .right
        renamePanel.children.append(apply)
        renameFlyout.content = renamePanel
        rename.flyout = renameFlyout
        keep(renameFlyout)
        keep(field)
        buttons.children.append(rename)

        // Delete…: only a profile no space uses, after Arc's warning.
        let delete = Button()
        delete.content = UI.text("Delete…", trimmed: false)
        delete.isEnabled = spaces.isEmpty
        let deleteFlyout = Flyout()
        let warning = StackPanel()
        warning.orientation = .vertical
        warning.spacing = 8
        warning.maxWidth = 300
        let question = UI.text("Delete “\(profile.name)”?", color: palette.text, trimmed: false)
        question.fontWeight = UWP.FontWeight(weight: 600)
        warning.children.append(question)
        let detail = UI.text("Deleting this Profile will permanently remove any cookies, history, preferences, and logins that belong to it.",
                             size: 12, color: palette.secondaryText, trimmed: false)
        detail.textWrapping = .wrap
        warning.children.append(detail)
        let confirm = Button()
        confirm.content = UI.text("Delete", trimmed: false)
        confirm.horizontalAlignment = .right
        confirm.click.addHandler { [weak deleteFlyout] _, _ in
            try? deleteFlyout?.hide()
            store.deleteProfile(profile.id)
        }
        warning.children.append(confirm)
        deleteFlyout.content = warning
        delete.flyout = deleteFlyout
        keep(deleteFlyout)
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
