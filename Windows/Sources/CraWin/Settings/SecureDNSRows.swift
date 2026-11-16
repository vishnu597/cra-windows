import CraCEFWin
import CraCore
import Foundation
import UWP
import WinUI

/// Chromium's secure DNS (chrome://settings/security) for Settings ▸ Privacy, read from and
/// written to Local State through the bridge (SecureDNSSetting on the Mac). Cra keeps no copy.
@MainActor
enum WinSecureDNS {
    /// What Chromium holds now; nil until Chromium is ready.
    static var prefs: SecureDNSPrefs? {
        guard let mode = cra_cef_secure_dns_preference("dns_over_https.mode").map({ String(cString: $0) }) else { return nil }
        let templates = cra_cef_secure_dns_preference("dns_over_https.templates").map { String(cString: $0) } ?? ""
        return SecureDNSPrefs(mode: mode, templates: templates)
    }

    /// A policy sets it, so the menu is read-only.
    static var isManaged: Bool { cra_cef_secure_dns_is_managed() != 0 }

    /// False when Chromium refused it (not ready, managed, write failed).
    static func apply(_ new: SecureDNSPrefs) -> Bool { cra_cef_set_secure_dns(new.mode, new.templates) != 0 }
}

/// The Secure DNS row under "Always use secure connections": a menu of Chrome's providers, and a
/// field for a custom template while Custom… is picked (the Mac's SecureDNSRows).
@MainActor
final class SecureDNSRows {
    let element = StackPanel()
    private let palette: SettingsPalette
    private var editingCustom = false
    private var customText = ""
    private var error: String?
    /// WinRT wrappers the handlers reach, kept for as long as the rows are shown.
    private var kept: [AnyObject] = []

    init(palette: SettingsPalette) {
        self.palette = palette
        element.orientation = .vertical
        draw()
    }

    private var current: SecureDNSChoice { WinSecureDNS.prefs?.choice ?? .automatic }
    private var liveCustom: String? { current == .custom ? WinSecureDNS.prefs?.templates : nil }
    private var showsCustom: Bool { editingCustom || current == .custom }

    /// Reads Chromium again and draws the rows (on showing the pane and after each change).
    func draw() {
        element.children.clear()
        kept = []
        let prefs = WinSecureDNS.prefs, managed = WinSecureDNS.isManaged
        var detail = "Before a page loads, the site’s address is looked up over an encrypted connection, so the network you’re on can’t see or change it."
        if let note = prefs.flatMap({ SecureDNS(mode: $0.mode, templates: $0.templates).footnote(managed: managed) }) { detail += " " + note }

        let shown = editingCustom ? SecureDNSChoice.custom : current
        let button = Button()
        button.content = UI.text(shown.title + "  ⌄", trimmed: false)
        button.isEnabled = prefs != nil && !managed
        try? AutomationProperties.setName(button, "Secure DNS")
        let menu = MenuFlyout()
        for (i, group) in SecureDNSChoice.menuGroups.enumerated() {
            if i > 0 { menu.items.append(MenuFlyoutSeparator()) }
            for choice in group {
                let item = ToggleMenuFlyoutItem()
                item.text = choice.title
                item.isChecked = choice == shown
                item.click.addHandler { [weak self] _, _ in self?.choose(choice) }
                menu.items.append(item)
            }
        }
        button.flyout = menu
        kept += [button, menu]
        element.children.append(SettingsPanes.cardRow("Secure DNS", detail: detail, trailing: button, palette: palette))

        if showsCustom {
            let field = TextBox()
            field.text = customText
            field.placeholderText = "https://dns.example/dns-query{?dns}"
            field.minWidth = 300
            field.isEnabled = !managed
            try? AutomationProperties.setName(field, "Custom provider")
            field.textChanged.addHandler { [weak self] _, _ in self?.customText = field.text }
            field.keyDown.addHandler { [weak self] _, args in
                guard let args, Int32(truncatingIfNeeded: args.key.rawValue) == 0x0D else { return }  // Return
                args.handled = true
                self?.saveCustom()
            }
            let use = UI.button("Use") { [weak self] in self?.saveCustom() }
            use.isEnabled = !managed
            kept += [field, use]
            let row = Grid()
            row.padding = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 0, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 10)
            row.columnSpacing = 8
            row.columnDefinitions.append(UI.column(UI.star))
            row.columnDefinitions.append(UI.column(UI.auto))
            row.children.append(field)
            row.children.append(use)
            try? Grid.setColumn(use, 1)
            element.children.append(row)
        }
        if let error {
            let line = UI.text(error, size: 11, color: UI.brush("#E5484D"), trimmed: false)
            line.textWrapping = .wrap
            line.margin = Thickness(left: Double(DiaSettingsMetrics.cardRowInset), top: 0, right: Double(DiaSettingsMetrics.cardRowInset), bottom: 10)
            element.children.append(line)
        }
    }

    private func choose(_ choice: SecureDNSChoice) {
        error = nil
        if choice == .custom {
            if !showsCustom { customText = "" }
            editingCustom = true
        } else {
            editingCustom = false
            if let prefs = SecureDNSPrefs(choice), !WinSecureDNS.apply(prefs) { error = "Cra couldn’t change secure DNS." }
        }
        if let live = liveCustom, !editingCustom { customText = live }
        draw()
    }

    private func saveCustom() {
        guard let prefs = SecureDNSPrefs(.custom, custom: customText) else {
            error = "Enter one or more https:// templates, like https://dns.example/dns-query{?dns}."
            return draw()
        }
        error = nil
        if WinSecureDNS.apply(prefs) {
            editingCustom = false
            customText = prefs.templates
        } else {
            error = "Cra couldn’t change secure DNS."
        }
        draw()
    }

    /// The pane showed again, or a setting changed: a choice made in chrome://settings/security
    /// shows here. Not while a custom template is being typed, which a redraw would cut off.
    func refresh() {
        guard !editingCustom else { return }
        if let live = liveCustom { customText = live }
        draw()
    }
}
