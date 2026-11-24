import CraCore
import Testing

/// A split pane's own bar and its Split View Options menu (Arc 1.171, GitHub #178).
struct SplitPaneOptionsMenuTests {
    @Test func theMenuMatchesArcs() {
        let titles = SplitPaneOptionsMenu.entries.map { $0?.title ?? "—" }
        #expect(titles == ["Separate Tab from Split", "Flip Split View Orientation", "—", "Copy Link", "—", "Close this Split Pane"])
        let actions = SplitPaneOptionsMenu.entries.compactMap { $0?.action }
        #expect(actions == ["separateFromSplit", "flipSplitOrientation", "copyURL", "closeSplitPane"])
    }

    @Test func eachPaneOfASplitHasABarOutsideFullscreen() {
        #expect(!SplitPaneOptionsMenu.barsShown(panes: 1, fullscreen: false))
        #expect(SplitPaneOptionsMenu.barsShown(panes: 2, fullscreen: false))
        #expect(SplitPaneOptionsMenu.barsShown(panes: 4, fullscreen: false))
        #expect(!SplitPaneOptionsMenu.barsShown(panes: 3, fullscreen: true))
    }

    /// An unfocused pane shows Arc's essentials until the pointer is over its bar.
    @Test func anUnfocusedPaneShowsItsEssentialsUntilHovered() {
        let quiet = ToolbarComposition(kind: .normal, inSplit: true, sidebarVisible: true, focusedPane: false, hovered: false,
                                       canGoBack: true, canGoForward: false, isLoading: false, pinnedExtensions: [])
        #expect(quiet.left == [.back(enabled: true), .forward(enabled: false)])
        #expect(quiet.right == [.closePane])
        let hovered = ToolbarComposition(kind: .normal, inSplit: true, sidebarVisible: true, focusedPane: false, hovered: true,
                                         canGoBack: true, canGoForward: false, isLoading: false, pinnedExtensions: [])
        #expect(hovered.right == [.extensions, .splitOptions, .closePane])
    }
}
