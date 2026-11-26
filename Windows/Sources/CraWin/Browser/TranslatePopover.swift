import CraCore
import Foundation
import UWP
import WinUI

/// Arc's translate popover (#310, the Mac's TranslatePopover): hung under the translate button
/// or the sidebar's "Translation Available", 236 DIPs wide. Arc's badge and its question
/// ("Translate this page to English?", or "Translated from French." on a translated page) over
/// two 104 × 32 buttons 7 apart: Options, flat (Choose Another Language ▸, Never Translate This
/// Site), and Translate, raised (Show Original on a translated page). Windows translates through
/// Google Translate's website (WebTranslate).
@MainActor
final class TranslatePopover {
    /// The sites Never Translate This Site named, kept in translate-never-sites.json (the Mac's
    /// are in Chromium's profile preferences, which Windows' stock CEF doesn't offer).
    @MainActor
    final class NeverSites {
        static let shared = NeverSites()
        private(set) var sites: Set<String>
        private let file: URL

        init(file: URL = WinPaths.supportDir.appendingPathComponent("translate-never-sites.json")) {
            self.file = file
            sites = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
        }

        func add(_ site: String) {
            guard sites.insert(site).inserted else { return }
            try? JSONEncoder().encode(sites.sorted()).write(to: file, options: .atomic)
        }
    }

    struct Actions {
        var translate: (_ target: String?) -> Void = { _ in }
        var showOriginal: () -> Void = {}
        var neverTranslateSite: () -> Void = {}
    }

    /// The flyout shown now; a WinRT control made in Swift lives only while Swift holds it.
    private var flyout: Flyout?
    private var kept: [AnyObject] = []

    func show(_ state: PageTranslation, under anchor: FrameworkElement, actions: Actions) {
        try? flyout?.hide()
        kept = []
        let flyout = Flyout()
        let panel = StackPanel()
        panel.orientation = .vertical
        panel.spacing = 12
        panel.width = 216

        let line = StackPanel()
        line.orientation = .horizontal
        line.spacing = 8
        let badge = FontIcon()
        badge.glyph = WinGlyph.code("character.bubble")
        badge.fontSize = 22
        badge.width = 32
        badge.verticalAlignment = .center
        line.children.append(badge)
        let prompt = UI.text(state.prompt, size: 14, trimmed: false)
        prompt.textWrapping = .wrap
        prompt.maxWidth = 176
        prompt.verticalAlignment = .center
        line.children.append(prompt)
        panel.children.append(line)

        let buttons = StackPanel()
        buttons.orientation = .horizontal
        buttons.spacing = 7
        let menu = MenuFlyout()
        let choose = MenuFlyoutSubItem()
        choose.text = "Choose Another Language"
        for code in state.otherLanguages {
            choose.items.append(UI.menuItem(PageTranslation.name(of: code)) { [weak flyout] in
                try? flyout?.hide()
                actions.translate(code)
            })
        }
        menu.items.append(choose)
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(UI.menuItem("Never Translate This Site") { [weak flyout] in
            try? flyout?.hide()
            actions.neverTranslateSite()
        })
        let options = UI.button(UI.text("Options", size: 14, trimmed: false), padding: Thickness(left: 0, top: 0, right: 0, bottom: 0)) {}
        options.flyout = menu
        let primary = Button()
        primary.content = UI.text(state.translated ? "Show Original" : "Translate", size: 14, trimmed: false)
        primary.clickMode = .press
        primary.click.addHandler { [weak flyout] _, _ in
            try? flyout?.hide()
            if state.translated { actions.showOriginal() } else { actions.translate(nil) }
        }
        for b in [options, primary] {
            b.width = 104
            b.height = 32
            b.horizontalContentAlignment = .center
            b.verticalContentAlignment = .center
            buttons.children.append(b)
        }
        panel.children.append(buttons)
        flyout.content = panel
        kept = [flyout, panel, line, badge, prompt, buttons, menu, choose, options, primary]
        self.flyout = flyout
        try? flyout.showAt(anchor)
    }

    func hide() {
        try? flyout?.hide()
        flyout = nil
    }
}
