import CraCore
import Foundation
import Testing

/// Arc's tab switcher on Ctrl+Tab: its cards and selection (Windows reads it; the Mac's
/// TabSwitcher keeps the same rules).
struct TabSwitcherCycleTests {
    let tabs = (0..<4).map { _ in UUID() }

    @Test func theFirstPressOpensOnTheNextCardOrTheLast() {
        var forward = TabSwitcherCycle(), backward = TabSwitcherCycle(), one = TabSwitcherCycle(), none = TabSwitcherCycle()
        let opened = [forward.open(tabs, delta: 1), backward.open(tabs, delta: -1), one.open([tabs[0]], delta: 1), none.open([], delta: 1)]
        #expect(opened == [true, true, true, false])
        #expect(forward.selected == tabs[1])
        #expect(backward.selected == tabs[3])
        #expect(one.selected == tabs[0])
        #expect(!none.isOpen)
    }

    @Test func movingWrapsRoundTheEnds() {
        var cycle = TabSwitcherCycle()
        _ = cycle.open(tabs, delta: 1)
        cycle.move(1); cycle.move(1); cycle.move(1)
        #expect(cycle.selectedIndex == 0)
        cycle.move(-1)
        #expect(cycle.selected == tabs[3])
        cycle.select(2)
        #expect(cycle.selected == tabs[2])
        cycle.select(9)
        #expect(cycle.selected == tabs[2], "no card there")
    }

    @Test func committingAnswersTheCardAndCancellingNothing() {
        var cycle = TabSwitcherCycle()
        _ = cycle.open(tabs, delta: 1)
        let committed = cycle.close(commit: true)
        #expect(committed == tabs[1] && !cycle.isOpen)
        _ = cycle.open(tabs, delta: 1)
        let cancelled = cycle.close(commit: false)
        #expect(cancelled == nil && !cycle.isOpen)
        let again = cycle.close(commit: true)
        #expect(again == nil, "closed already")
    }

    @Test func theCardsLeaveOutUnloadedPinnedTabsAndStopAtFive() {
        let ids = (0..<8).map { _ in UUID() }
        let pinned: Set<UUID> = [ids[1], ids[2], ids[0]]
        let loaded: Set<UUID> = [ids[2]]
        let cards = TabSwitcherCycle.cards(recent: ids, selected: ids[0], isPinned: pinned.contains, isLoaded: loaded.contains)
        // The open pinned tab stays, the loaded one too, the unloaded one goes.
        #expect(cards == [ids[0], ids[2], ids[3], ids[4], ids[5]])
    }

    @Test func thePanelIsArcsSize() {
        #expect(TabSwitcherLayout.panelSize(count: 3) == CGSize(width: 577, height: 190))
        #expect(TabSwitcherLayout.panelSize(count: 0) == TabSwitcherLayout.panelSize(count: 1))
        #expect(TabSwitcherLayout.windowSize(count: 1).width == 213 + 80)
    }

    @Test func theSelectedCardTakesTheSpacesHue() {
        let grey = SpaceTheme.presets[0]
        let dark = grey.switcherHighlightRGBA(dark: true), light = grey.switcherHighlightRGBA(dark: false)
        #expect(dark.a == 0.48 && light.a == 1)
        for c in [dark, light] { #expect((0...1).contains(c.r) && (0...1).contains(c.g) && (0...1).contains(c.b)) }
        var red = grey
        red.accent = "#FF0000"
        let r = red.switcherHighlightRGBA(dark: true)
        #expect(r.r > r.g && r.r > r.b, "a red space's card is red")
        var none = grey
        none.accent = "#808080"
        let g = none.switcherHighlightRGBA(dark: true)
        #expect(abs(g.r - g.g) < 0.01 && abs(g.g - g.b) < 0.01, "a grey space's card stays grey")
    }
}
