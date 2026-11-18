import CraCore
import Foundation
import Testing

/// A tab or link let go on the panes where SplitDropProposal offered a split (the Mac's
/// PageSplitDrop.drop, which Windows' window calls through CraCore).
@MainActor
struct SplitDropTests {
    private func tabs(_ f: StoreFixture, _ n: Int) -> [UUID] {
        f.store.settings.newTabsAtTop = false
        return (0..<n).map { f.store.createTab(url: "https://\($0).test/").id }
    }

    @Test func aTabOnALonePageMakesASplitOnThatSide() {
        let f = StoreFixture()
        let t = tabs(f, 2)
        let window = f.store.activeWindowID
        let pane = SplitDrop.drop(.tab(t[1]), at: .insert(.init(index: 0, orientation: .vertical)), panes: [t[0]],
                                  splitOrientation: .horizontal, store: f.store, window: window)
        #expect(pane == t[1])
        let split = f.store.splitContaining(t[0])
        #expect(split?.children == [t[1], t[0]] && split?.split?.orientation == .vertical)
        #expect(f.store.selectedTabID(window: window) == t[1])
        #expect(f.sound)
    }

    @Test func aTabInASplitTakesItsPlaceAndAReplacedPaneLeaves() {
        let f = StoreFixture()
        let t = tabs(f, 4)
        let window = f.store.activeWindowID
        SplitDrop.drop(.tab(t[1]), at: .insert(.init(index: 1, orientation: .horizontal)), panes: [t[0]],
                       splitOrientation: .horizontal, store: f.store, window: window)
        SplitDrop.drop(.tab(t[2]), at: .insert(.init(index: 1, orientation: .horizontal)), panes: [t[0], t[1]],
                       splitOrientation: .horizontal, store: f.store, window: window)
        #expect(f.store.splitContaining(t[0])?.children == [t[0], t[2], t[1]])
        // The middle pane gives its place to the new tab and goes back to the sidebar.
        SplitDrop.drop(.tab(t[3]), at: .replace(index: 1), panes: [t[0], t[2], t[1]], splitOrientation: .horizontal, store: f.store, window: window)
        #expect(f.store.splitContaining(t[0])?.children == [t[0], t[3], t[1]])
        #expect(f.store.splitContaining(t[2]) == nil)
        #expect(f.sound)
    }

    @Test func aPaneOrAFullSplitTakesNothing() {
        let f = StoreFixture()
        let t = tabs(f, 5)
        let window = f.store.activeWindowID
        let right = SplitDropProposal.Target.insert(.init(index: 1, orientation: .horizontal))
        #expect(SplitDrop.drop(.tab(t[0]), at: right, panes: [t[0]], splitOrientation: .horizontal, store: f.store, window: window) == nil)
        #expect(SplitDrop.drop(.tab(t[4]), at: right, panes: Array(t[0..<4]), splitOrientation: .horizontal, store: f.store, window: window) == nil)
        #expect(SplitDrop.drop(.tab(t[1]), at: .replace(index: 0), panes: [t[0]], splitOrientation: .horizontal, store: f.store, window: window) == nil)
    }

    @Test func aLinkOpensInANewPane() {
        let f = StoreFixture()
        let t = tabs(f, 1)
        let window = f.store.activeWindowID
        let pane = SplitDrop.drop(.link(.init(url: "https://link.test/", title: "Link")), at: .insert(.init(index: 1, orientation: .horizontal)),
                                  panes: [t[0]], splitOrientation: .horizontal, store: f.store, window: window)
        #expect(pane != nil && f.store.item(pane!)?.tab?.url == "https://link.test/")
        #expect(f.store.splitContaining(t[0])?.children.first == t[0])
        #expect(SplitDrop.Payload.link(.init(url: "https://x.test/", title: "")).isLink)
    }

    @Test func thePressedTabGivesWayToThePageFromBeforeThePress() {
        let f = StoreFixture()
        let t = tabs(f, 3)
        #expect(SplitDrop.showing(dragging: t[1], panes: [t[0]], before: nil, store: f.store) == .asIs)
        #expect(SplitDrop.showing(dragging: t[1], panes: [t[1]], before: t[0], store: f.store) == .swap(to: t[0]))
        #expect(SplitDrop.showing(dragging: t[1], panes: [t[1]], before: t[1], store: f.store) == .refused)
        #expect(SplitDrop.showing(dragging: t[1], panes: [t[1], t[2]], before: t[0], store: f.store) == .refused)
    }
}
