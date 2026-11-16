import CraCore
import Foundation
import Testing

/// Drops on a space's list, its favorites and its icon, as Windows' sidebar asks for them (the
/// Mac's SpaceListView.resolve and applyDrop).
@MainActor
struct SidebarDropPlanTests {
    /// Rows 30 high with 2 between them, pinned first, a 10-high divider, then Today.
    private func layout(_ f: StoreFixture, expanded: [UUID: [UUID]] = [:]) -> SidebarDropPlan.Layout {
        var rows: [SidebarDropPlan.Row] = []
        var y = 0.0
        func add(_ ids: [UUID], parent: UUID, depth: Int) {
            for (i, id) in ids.enumerated() {
                rows.append(.init(itemID: id, parent: parent, index: i, depth: depth, minY: y, maxY: y + 30, minX: 0, maxX: 200))
                y += 32
                if let kids = expanded[id] { add(kids, parent: id, depth: depth + 1) }
            }
        }
        add(f.pinned(), parent: f.space.pinnedContainerID, depth: 0)
        let pinnedMaxY = y
        y += 10
        let todayMinY = y
        add(f.today(), parent: f.space.todayContainerID, depth: 0)
        return .init(rows: rows, pinnedMinY: 0, pinnedMaxY: pinnedMaxY, todayMinY: todayMinY, rowSpacing: 2)
    }

    private func todayTabs(_ f: StoreFixture, _ n: Int) -> [UUID] {
        f.store.settings.newTabsAtTop = false
        return (0..<n).map { f.store.createTab(url: "https://\($0).test/").id }
    }

    private func resolve(_ f: StoreFixture, _ id: UUID, _ x: Double = 50, _ y: Double, expanded: [UUID: [UUID]] = [:]) -> SidebarDropPlan.Drop {
        SidebarDropPlan.resolve(dragged: id, at: (x, y), layout: layout(f, expanded: expanded), space: f.space.id, store: f.store)
    }

    @Test func theTopQuarterOfARowPutsTheItemBeforeIt() {
        let f = StoreFixture()
        let t = todayTabs(f, 3)
        // Today starts at 10; the first row's top quarter.
        let drop = resolve(f, t[2], 12)
        #expect(drop.target == .insert(parent: f.space.todayContainerID, index: 0))
        #expect(drop.lineY == 9 && drop.lineDepth == 0 && drop.rowBelow == t[0])
        #expect(SidebarDropPlan.apply(drop, store: f.store, window: f.store.activeWindowID))
        #expect(f.today() == [t[2], t[0], t[1]])
        #expect(f.sound)
    }

    @Test func letGoBesideItselfNothingMoves() {
        let f = StoreFixture()
        let t = todayTabs(f, 3)
        // The bottom quarter of the row above it, and its own row.
        #expect(resolve(f, t[1], 10 + 30 - 2).target == nil)
        #expect(resolve(f, t[1], 10 + 32 + 15).target == nil)
        #expect(!SidebarDropPlan.apply(resolve(f, t[1], 10 + 32 + 15), store: f.store, window: f.store.activeWindowID))
        #expect(f.today() == t)
    }

    @Test func aTabsMiddleMakesASplitOnTheSideThePointerIsOn() {
        let f = StoreFixture()
        let t = todayTabs(f, 3)
        let middle = 10 + 15.0
        #expect(resolve(f, t[2], 40, middle).target == .split(with: t[0], leading: true))
        let drop = resolve(f, t[2], 160, middle)
        #expect(drop.target == .split(with: t[0], leading: false) && drop.lineY == nil && drop.combineRow == t[0])
        #expect(SidebarDropPlan.apply(drop, store: f.store, window: f.store.activeWindowID))
        let split = f.store.splitContaining(t[0])
        #expect(split != nil && split?.children == [t[0], t[2]])
        // Arc opens the tab the drag picked up.
        #expect(f.store.selectedTabID(window: f.store.activeWindowID) == t[2])
        #expect(f.sound)
    }

    @Test func aFolderTakesWhatIsLetGoOnItsMiddle() {
        let f = StoreFixture()
        let t = todayTabs(f, 2)
        let folder = f.store.createFolder(named: "Work", in: f.space.pinnedContainerID)
        f.store.setExpanded(folder.id, false)
        let drop = resolve(f, t[1], 15)
        #expect(drop.target == .into(folder.id) && drop.combineRow == folder.id)
        #expect(SidebarDropPlan.apply(drop, store: f.store, window: f.store.activeWindowID))
        #expect(f.store.item(t[1])?.parentID == folder.id)
        #expect(f.sound)
    }

    @Test func anOpenFoldersBottomPutsTheItemFirstInside() {
        let f = StoreFixture()
        let t = todayTabs(f, 2)
        let folder = f.store.createFolder(named: "Work", in: f.space.pinnedContainerID)
        f.store.moveItem(t[0], to: folder.id, index: nil)
        f.store.setExpanded(folder.id, true)
        let drop = resolve(f, t[1], 28, expanded: [folder.id: [t[0]]])
        #expect(drop.target == .insert(parent: folder.id, index: 0))
        #expect(drop.lineDepth == 1 && drop.rowBelow == t[0])
    }

    @Test func aFolderNeverGoesIntoItself() {
        let f = StoreFixture()
        let outer = f.store.createFolder(named: "Outer", in: f.space.pinnedContainerID)
        let inner = f.store.createFolder(named: "Inner", in: outer.id)
        f.store.setExpanded(outer.id, true)
        f.store.setExpanded(inner.id, false)
        // Inner's middle, the second row.
        #expect(resolve(f, outer.id, 32 + 15, expanded: [outer.id: [inner.id]]).target == nil)
    }

    @Test func pastTheRowsItGoesToTheEndOfASection() {
        let f = StoreFixture()
        let t = todayTabs(f, 2)
        let pinned = f.store.createTab(url: "https://pinned.test/", pinned: true)
        // Under Today's last row, and just over the divider.
        #expect(resolve(f, t[0], 400).target == .insert(parent: f.space.todayContainerID, index: 2))
        let up = resolve(f, t[0], 33)
        #expect(up.target == .insert(parent: f.space.pinnedContainerID, index: 1) && up.lineY == 31 && up.rowAbove == pinned.id)
        #expect(SidebarDropPlan.apply(up, store: f.store, window: f.store.activeWindowID))
        #expect(f.pinned() == [pinned.id, t[0]] && f.store.isPinned(t[0]))
    }

    @Test func aLinkCombinesWithNothingButAFolder() {
        let f = StoreFixture()
        let t = todayTabs(f, 2)
        let folder = f.store.createFolder(named: "Reading", in: f.space.pinnedContainerID)
        f.store.setExpanded(folder.id, false)
        let link = SidebarDropPlan.link
        let window = f.store.activeWindowID
        // A tab's middle takes nothing.
        #expect(resolve(f, link, 32 + 10 + 15).target == nil)
        // A folder's middle takes it in at the top, without opening the tab.
        let into = resolve(f, link, 15)
        #expect(into.isLink && into.target == .into(folder.id))
        let selected = f.store.selectedTabID(window: window)
        let tab = SidebarDropPlan.dropLink(SidebarLinkDrop.Tab(url: "https://link.test/", title: "Link"), drop: into,
                                           space: f.space.id, store: f.store, window: window)
        #expect(tab?.parentID == folder.id && f.store.item(folder.id)?.children.first == tab?.id)
        #expect(f.store.selectedTabID(window: window) == selected)
        // Between two tabs it lands between them; a link never moves a row.
        let between = resolve(f, link, 32 + 10 + 30)
        #expect(between.target == .insert(parent: f.space.todayContainerID, index: 1))
        #expect(!SidebarDropPlan.apply(between, store: f.store, window: window))
        #expect(f.today() == t)
    }

    @Test func favoritesTakeATabInTheSlotItIsLetGoIn() {
        let f = StoreFixture()
        let t = todayTabs(f, 4)
        f.store.addToFavorites(t[0])
        f.store.addToFavorites(t[1])
        #expect(SidebarDropPlan.dropOnFavorites(t[2], slot: 1, space: f.space.id, store: f.store))
        #expect(f.favorites() == [t[0], t[2], t[1]])
        // A favorite moves to its new slot.
        #expect(SidebarDropPlan.dropOnFavorites(t[1], slot: 0, space: f.space.id, store: f.store))
        #expect(f.favorites() == [t[1], t[0], t[2]])
        // Past the last slot it goes at the end.
        #expect(SidebarDropPlan.dropOnFavorites(t[3], slot: 9, space: f.space.id, store: f.store))
        #expect(f.favorites().last == t[3])
        // A folder can't be a favorite.
        let folder = f.store.createFolder(named: "F", in: f.space.pinnedContainerID)
        #expect(!SidebarDropPlan.dropOnFavorites(folder.id, slot: 0, space: f.space.id, store: f.store))
        #expect(f.sound)
    }

    @Test func aSpacesIconTakesTheTabToThatSpace() {
        let f = StoreFixture()
        let t = todayTabs(f, 2)
        let other = f.store.createSpace(title: "Work", emoji: "💼")
        #expect(SidebarDropPlan.dropOnSpace(t[1], space: other.id, store: f.store))
        #expect(f.store.spaceID(ofItem: t[1]) == other.id && f.store.spaceID(ofItem: t[0]) != other.id)
        #expect(f.sound)
    }

    @Test func aDraggedSpaceIconLandsInTheCellItIsLetGoIn() {
        let f = StoreFixture()
        let first = f.store.spaceOrder[0]
        let b = f.store.createSpace(title: "B", emoji: "🅱️").id
        let c = f.store.createSpace(title: "C", emoji: "🌊").id
        let shown = f.store.spaceOrder
        #expect(SidebarDropPlan.spaceOrderIndex(moving: first, toCell: 2, shown: shown, store: f.store) == 2)
        #expect(SidebarDropPlan.spaceOrderIndex(moving: first, toCell: 0, shown: shown, store: f.store) == nil)
        f.store.moveSpace(first, to: 2)
        #expect(f.store.spaceOrder == [b, c, first])
    }
}
