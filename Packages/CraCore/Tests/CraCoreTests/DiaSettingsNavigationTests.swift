#if canImport(CoreGraphics)
import CoreGraphics
#endif
import CraCore
import Foundation
import Testing

/// The Settings window's sidebar and its back/forward pill (Dia 1.54.2).
@MainActor
struct DiaSettingsNavigationTests {
    @Test func opensOnGeneral() {
        let nav = DiaSettingsNavigation()
        #expect(nav.pane == .general && nav.back.isEmpty && nav.forward.isEmpty && !nav.isOpen)
        #expect(DiaSettingsNavigation(pane: .tabs).pane == .tabs)
    }

    @Test func showingAPaneRemembersTheOneBefore() {
        let nav = DiaSettingsNavigation()
        nav.show(.tabs)
        nav.show(.privacy)
        #expect(nav.pane == .privacy && nav.back == [.general, .tabs])
        nav.show(.privacy)
        #expect(nav.back == [.general, .tabs], "the pane already shown adds nothing")
    }

    @Test func backAndForwardWalkTheHistory() {
        let nav = DiaSettingsNavigation()
        nav.show(.tabs)
        nav.show(.advanced)
        nav.goBack()
        #expect(nav.pane == .tabs && nav.forward == [.advanced])
        nav.goBack()
        #expect(nav.pane == .general && nav.back.isEmpty && nav.forward == [.advanced, .tabs])
        nav.goBack()
        #expect(nav.pane == .general, "nothing further back")
        nav.goForward()
        #expect(nav.pane == .tabs && nav.back == [.general])
        nav.show(.profiles)
        #expect(nav.forward.isEmpty, "a new pane drops what was ahead")
        nav.goForward()
        #expect(nav.pane == .profiles)
    }

    @Test func panesHaveTitlesInDiasOrder() {
        #expect(DiaSettingsPane.allCases.map(\.title) == ["General", "Tabs", "Links", "Max", "Privacy", "Profiles", "Extensions", "Plugins", "Shortcuts",
                                                       "Performance", "Advanced"])
        #expect(DiaSettingsPane.tabs.id == "tabs")
        #expect(DiaSettingsPane.windowsPanes.allSatisfy { DiaSettingsPane.allCases.contains($0) })
        let order = DiaSettingsPane.windowsPanes.compactMap { DiaSettingsPane.allCases.firstIndex(of: $0) }
        #expect(order == order.sorted(), "in the Mac's order")
        #expect(DiaSettingsPane.windowsPanes == [.general, .tabs, .profiles, .shortcuts])
    }

    /// Dia's measurements: the content column fits beside the sidebar, the form's controls start
    /// after its labels, and cards fit their rows.
    @Test func diasGeometryAddsUp() {
        let content = DiaSettingsMetrics.windowSize.width - DiaSettingsMetrics.sidebarWidth
        #expect(DiaSettingsMetrics.windowSize == CGSize(width: 778, height: 509) && content == 574)
        #expect(DiaSettingsMetrics.formControlX > DiaSettingsMetrics.formLabelWidth && DiaSettingsMetrics.formControlX < content)
        #expect(DiaSettingsMetrics.navPillSize.height < DiaSettingsMetrics.toolbarHeight)
        #expect(DiaSettingsMetrics.paneInset * 2 < content && DiaSettingsMetrics.paneTop > 0 && DiaSettingsMetrics.formTop > 0)
        #expect(DiaSettingsMetrics.cardRowInset * 2 < DiaSettingsMetrics.cardRowHeight && DiaSettingsMetrics.cardCorner > 0)
        #expect(DiaSettingsMetrics.formGroupSpacing > 0)
        // Shortcuts: the list leaves room for the detail column beside it.
        #expect(DiaSettingsMetrics.shortcutsListWidth + DiaSettingsMetrics.shortcutsInset * 2 < content - 200)
        #expect(DiaSettingsMetrics.shortcutsRowHeight == 36)
    }
}
