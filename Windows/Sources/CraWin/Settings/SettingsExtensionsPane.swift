import CraCore
import Foundation
import WinUI

extension SettingsPanes {
    /// Dia's Extensions pane (ExtensionsPane on the Mac): each installed extension with Remove
    /// (one of Cra's own folders) or Remove… (Chromium's install, removed in chrome://extensions),
    /// then Add Unpacked Extension… and Open Chrome's Extension Manager under the card. Windows
    /// lists every profile's installs once each. `owner` is the Settings window (the folder
    /// picker's owner); `openURL` opens a page in the browser window in use.
    static func extensions(store: SidebarStore, palette: SettingsPalette, owner: @escaping @MainActor () -> UInt,
                           openURL: @escaping @MainActor (String) -> Void) -> SettingsPaneContent {
        let stack = StackPanel()
        stack.orientation = .vertical
        stack.margin = Thickness(left: Double(DiaSettingsMetrics.paneInset), top: Double(DiaSettingsMetrics.paneTop),
                                 right: Double(DiaSettingsMetrics.paneInset), bottom: 20)
        stack.children.append(header("Installed extensions", palette: palette))
        let holder = Border()
        stack.children.append(holder)

        let buttons = Grid()
        buttons.margin = Thickness(left: 0, top: 7.5, right: 0, bottom: 0)
        buttons.columnDefinitions.append(UI.column(UI.auto))
        buttons.columnDefinitions.append(UI.column(UI.star))
        buttons.columnDefinitions.append(UI.column(UI.auto))
        let add = Button()
        add.content = UI.text("Add Unpacked Extension…", trimmed: false)
        buttons.children.append(add)
        let manage = Button()
        manage.content = UI.text("Open Chrome’s Extension Manager", trimmed: false)
        manage.click.addHandler { _, _ in openURL(SiteControlCenter.manageExtensionsURL) }
        buttons.children.append(manage)
        try? Grid.setColumn(manage, 2)
        stack.children.append(buttons)

        let error = UI.text("", size: 11, color: palette.error, trimmed: false)
        error.textWrapping = .wrap
        error.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 10, right: 0, bottom: 0)
        error.visibility = .collapsed
        stack.children.append(error)
        let footnote = UI.text("", size: 11, color: palette.secondaryText, trimmed: false)
        footnote.textWrapping = .wrap
        footnote.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 10, right: 0, bottom: 0)
        stack.children.append(footnote)

        func show(error text: String?) {
            error.text = text ?? ""
            error.visibility = text == nil ? .collapsed : .visible
        }

        // nil until the first build, so an empty list still draws its card.
        var shown: String?
        // The rows' buttons, which their handlers need: a WinRT control built from Swift is only
        // a wrapper, gone once nothing in Swift holds it.
        var kept: [AnyObject] = []
        func rebuild() {
            let list = ExtensionList.shared
            footnote.text = list.needsRestart ? "Restart Cra to apply the change."
                : "Extensions you add here load when Cra starts, in every profile. Ones from the Chrome Web Store work at once."
            let entries = installed(store: store)
            let signature = entries.map { "\($0.id)|\($0.folder.path)|\($0.manifest.version)|\($0.isEnabled)" }.joined(separator: "\n")
            guard signature != shown else { return }
            shown = signature
            var parts: [AnyObject] = []
            if entries.isEmpty {
                let empty = UI.text("No extensions installed. Add one from the Chrome Web Store, or an unpacked extension folder (the kind Chrome’s “Load unpacked” takes).",
                                    color: palette.secondaryText, trimmed: false)
                empty.textWrapping = .wrap
                empty.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 12, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 12)
                holder.child = card([empty], palette: palette)
            } else {
                let shared = ExtensionFolders.sharedNames(entries.map(\.name))
                holder.child = card(entries.map { e in
                    extensionRow(e, showsFolder: shared.contains(e.name), palette: palette, keep: { parts.append($0) }) {
                        if e.inCraFolder {
                            do {
                                try FileManager.default.removeItem(at: e.folder)
                                list.needsRestart = true
                                show(error: nil)
                            } catch {
                                show(error: "\(e.name) couldn’t be removed: \(error.localizedDescription)")
                            }
                            rebuild()
                        } else {
                            openURL("chrome://extensions/?id=\(e.id)")
                        }
                    }
                }, palette: palette)
            }
            kept = parts
        }

        add.click.addHandler { _, _ in
            guard let folder = WinShell.pickFolder(owner: owner(), title: "Choose an unpacked extension folder (it holds manifest.json)")
            else { return }
            do {
                try ExtensionFolders.add(folder: folder, to: WinPaths.extensions)
                ExtensionList.shared.needsRestart = true
                show(error: nil)
            } catch {
                show(error: error.localizedDescription)
            }
            rebuild()
        }
        rebuild()
        return SettingsPaneContent(element: stack) { rebuild() }
    }

    /// Default's and each profile's extensions, once each, by name; and Cra's folders that
    /// haven't loaded yet (added this session), which Chromium lists from the next launch.
    private static func installed(store: SidebarStore) -> [ExtensionList.Entry] {
        let list = ExtensionList.shared
        let paths: [String?] = [nil] + store.profiles.map { store.profilePath(profile: $0.id) }
        var seen = Set<String>()
        var entries: [ExtensionList.Entry] = []
        for path in paths {
            for e in list.entries(profilePath: path, chromiumCache: store.chromiumCache) where seen.insert(e.folder.standardizedFileURL.path).inserted {
                entries.append(e)
            }
        }
        for folder in ExtensionFolders.loadable(in: WinPaths.extensions) where seen.insert(folder.standardizedFileURL.path).inserted {
            guard let manifest = ExtensionManifest(folder: folder, fallbackName: folder.lastPathComponent), !manifest.isThemeOrApp else { continue }
            entries.append(ExtensionList.Entry(id: folder.lastPathComponent, name: manifest.name, isEnabled: true, folder: folder, manifest: manifest))
        }
        return entries.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    /// `showsFolder`: another row has the same name, so this one names its folder too.
    private static func extensionRow(_ e: ExtensionList.Entry, showsFolder: Bool, palette: SettingsPalette, keep: (AnyObject) -> Void,
                                     remove: @escaping @MainActor () -> Void) -> Grid {
        let row = Grid()
        row.minHeight = Double(DiaSettingsMetrics.cardRowHeight) + 8
        row.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 6, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 6)
        row.columnDefinitions.append(UI.column(UI.star))
        row.columnDefinitions.append(UI.column(UI.auto))
        let labels = StackPanel()
        labels.orientation = .vertical
        labels.verticalAlignment = .center
        labels.margin = Thickness(left: 0, top: 0, right: 12, bottom: 0)
        let version = e.manifest.version.isEmpty ? "" : " \(e.manifest.version)"
        labels.children.append(UI.text(e.name + version + (e.isEnabled ? "" : " (turned off)"), color: palette.text))
        if !e.manifest.description.isEmpty {
            let description = UI.text(e.manifest.description, size: 11, color: palette.secondaryText, trimmed: false)
            description.textWrapping = .wrap
            description.maxLines = 2
            labels.children.append(description)
        }
        if showsFolder {
            labels.children.append(UI.text("Folder: \(e.folder.lastPathComponent)", size: 11, color: palette.secondaryText))
        }
        row.children.append(labels)
        let button = Button()
        button.content = UI.text(e.inCraFolder ? "Remove" : "Remove…", trimmed: false)
        button.verticalAlignment = .center
        button.click.addHandler { _, _ in remove() }
        row.children.append(button)
        try? Grid.setColumn(button, 1)
        keep(button)
        return row
    }
}
