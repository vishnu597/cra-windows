import CraCore
import Testing

/// One window's line of permission requests: only a tab on screen asks, one card at a time, and
/// a card whose tab goes behind waits for it again (#286, #371).
struct PermissionLineTests {
    struct Ask: Equatable { let tab: Int; let site: String }

    func same(_ change: (aside: Ask?, next: Ask?), _ aside: Ask?, _ next: Ask?) -> Bool {
        change.aside == aside && change.next == next
    }

    // #286: a tab behind asked over the tab in front. Its request waits until its tab is shown.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/286")) func aTabBehindWaitsUntilItIsShown() {
        var line = PermissionLine<Ask>()
        let meet = Ask(tab: 2, site: "meet")
        let asksA = line.add(meet, tabShown: false)
        #expect(!asksA)
        #expect(line.asking == nil)
        #expect(line.waiting == [meet])
        // Another tab in front: still waiting.
        let change1 = line.tabsChanged { $0.tab == 1 }
        #expect(same(change1, nil, nil))
        // Its tab comes to the front: it asks.
        let shown = line.tabsChanged { $0.tab == 2 }
        #expect(shown.aside == nil && shown.next == meet)
        #expect(line.asking == meet && line.waiting.isEmpty)
        let finished = line.finish()
        #expect(finished == meet)
        #expect(line.isEmpty)
    }

    @Test func oneCardAtATimeOldestFirst() {
        var line = PermissionLine<Ask>()
        let a = Ask(tab: 1, site: "a"), b = Ask(tab: 1, site: "b"), c = Ask(tab: 3, site: "c")
        let asksA = line.add(a, tabShown: true)
        #expect(asksA)
        let asksB = line.add(c, tabShown: false)
        #expect(!asksB)
        let asksC = line.add(b, tabShown: true)
        #expect(!asksC)
        #expect(line.all == [a, c, b])
        line.finish()
        // c's tab is still behind, so b (on screen) asks next.
        let change2 = line.tabsChanged { $0.tab == 1 }
        #expect(same(change2, nil, b))
        #expect(line.waiting == [c])
        // A card is up: nothing else asks, even with c's tab shown too.
        let change3 = line.tabsChanged { $0.tab == 1 || $0.tab == 3 }
        #expect(same(change3, nil, nil))
    }

    // #371: the card's tab went behind; the card goes unanswered and its request waits first in
    // line, then asks again when its tab is back.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/371")) func aCardWhoseTabGoesBehindStepsAside() {
        var line = PermissionLine<Ask>()
        let a = Ask(tab: 1, site: "a"), b = Ask(tab: 2, site: "b")
        let asksA = line.add(a, tabShown: true)
        #expect(asksA)
        let asksB = line.add(b, tabShown: true)
        #expect(!asksB)
        // Tab 2 to the front: a steps aside, b asks.
        let change4 = line.tabsChanged { $0.tab == 2 }
        #expect(same(change4, a, b))
        #expect(line.asking == b && line.waiting == [a])
        line.finish()
        let change5 = line.tabsChanged { $0.tab == 1 }
        #expect(same(change5, nil, a))
    }

    @Test func aClosedPageLeavesTheLine() {
        var line = PermissionLine<Ask>()
        let a = Ask(tab: 1, site: "a"), b = Ask(tab: 2, site: "b"), c = Ask(tab: 1, site: "c")
        _ = line.add(a, tabShown: true)
        _ = line.add(b, tabShown: false)
        _ = line.add(c, tabShown: true)
        let gone = line.remove { $0.tab == 1 }
        #expect(gone.removed == [a, c] && gone.wasAsking)
        #expect(line.asking == nil && line.waiting == [b])
        let none = line.remove { $0.tab == 5 }
        #expect(none.removed.isEmpty && !none.wasAsking)
    }
}
