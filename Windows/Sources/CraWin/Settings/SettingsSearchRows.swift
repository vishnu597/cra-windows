import CraCore
import Foundation
import WinUI

/// The command bar's settings, where the Mac has them: the search engine and its suggestions in
/// Profiles (ProfilesPane's first card, where Arc has them), and Advanced's Command bar card (the site's
/// colour, #457, and this space's tabs only, #307).
@MainActor
extension SettingsPanes {
    /// Profiles: Search engine (Cra's list: Windows reads no Chromium engine list yet) and Include
    /// search engine suggestions. The command bar's search-suggestions notice opens this pane.
    static func searchCard(store: SidebarStore, palette: SettingsPalette, syncs: inout [() -> Void]) -> Border {
        let engines = SearchEngine.allCases
        let picker = ComboBox()
        picker.verticalAlignment = .center
        picker.minWidth = 140
        for e in engines { picker.items.append(e.label) }
        picker.selectedIndex = Int32(engines.firstIndex(of: store.settings.searchEngine) ?? 0)
        picker.selectionChanged.addHandler { [weak picker] _, _ in
            guard let picker else { return }
            let i = Int(picker.selectedIndex)
            guard engines.indices.contains(i), store.settings.searchEngine != engines[i] else { return }
            store.settings.searchEngine = engines[i]
        }
        try? AutomationProperties.setName(picker, "Search engine")
        // The sync holds the picker: its handler's weak capture needs a Swift owner.
        syncs.append {
            let i = Int32(engines.firstIndex(of: store.settings.searchEngine) ?? 0)
            if picker.selectedIndex != i { picker.selectedIndex = i }
        }
        return card([
            cardRow("Search engine", trailing: picker, palette: palette),
            settingSwitch("Include search engine suggestions", detail: nil, \.searchSuggestions, store: store, palette: palette, syncs: &syncs),
        ], palette: palette)
    }

    /// Advanced's Command bar card.
    static func commandBarSection(store: SidebarStore, palette: SettingsPalette, syncs: inout [() -> Void]) -> [UIElement] {
        [
            header("Command bar", palette: palette),
            card([
                // GitHub #457, not in Arc: Arc's bar stays neutral, with the site in the pill.
                settingSwitch("Fill the command bar with the site’s color",
                              detail: "When Tab starts a search on a site, like YouTube or GitHub, the command bar takes that site’s color until you leave the search.",
                              \.commandBarSiteColor, store: store, palette: palette, syncs: &syncs),
                // GitHub #307, not in Arc: Ctrl+T finds tabs in the window's space only.
                settingSwitch("Only this space’s tabs",
                              detail: "The command bar finds open tabs in the space you’re in, not in all your spaces.",
                              \.commandBarCurrentSpaceOnly, store: store, palette: palette, syncs: &syncs),
            ], palette: palette),
        ]
    }
}
