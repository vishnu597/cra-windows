import Foundation

/// What letting go of a sidebar drag over a space's list does, from the rows where they are on
/// screen: the rule of the Mac's `SpaceListView.resolve` and `applyDrop`, for sidebars that lay
/// their rows out another way (Windows' XAML list). The top and bottom quarters of a row insert
/// before and after it; its middle combines: a folder takes the item, a tab (pinned or not)
/// makes a split in its place on the side of the row the pointer is on, a split row takes a
/// pane. A link from a page or another app (#419) combines with nothing: a tab's or split's
/// middle takes nothing, a folder's middle takes it in at the top.
public enum SidebarDropPlan {
    public enum Target: Equatable, Sendable {
        /// Before the child at `index` of `parent` (`index == count` appends).
        case insert(parent: UUID, index: Int)
        /// A split of this tab and the dragged one; the dragged tab takes the left pane when
        /// `leading`, else the right.
        case split(with: UUID, leading: Bool)
        /// Into a folder or a split row.
        case into(UUID)
    }

    /// One item's row in the list, in the list's coordinates (y grows down).
    public struct Row: Equatable, Sendable {
        public var itemID: UUID
        /// The container it sits in, and its place there.
        public var parent: UUID
        public var index: Int
        /// Folder levels in from the list's left.
        public var depth: Int
        public var minY: Double
        public var maxY: Double
        public var minX: Double
        public var maxX: Double

        public init(itemID: UUID, parent: UUID, index: Int, depth: Int, minY: Double, maxY: Double, minX: Double, maxX: Double) {
            self.itemID = itemID
            self.parent = parent
            self.index = index
            self.depth = depth
            self.minY = minY
            self.maxY = maxY
            self.minX = minX
            self.maxX = maxX
        }

        var midX: Double { (minX + maxX) / 2 }
    }

    /// The list as drawn: its item rows top to bottom, where the pinned section ends and Today
    /// begins (the divider between them), and the gap between rows.
    public struct Layout: Equatable, Sendable {
        public var rows: [Row]
        public var pinnedMinY: Double
        public var pinnedMaxY: Double
        public var todayMinY: Double
        public var rowSpacing: Double

        public init(rows: [Row], pinnedMinY: Double, pinnedMaxY: Double, todayMinY: Double, rowSpacing: Double) {
            self.rows = rows
            self.pinnedMinY = pinnedMinY
            self.pinnedMaxY = pinnedMaxY
            self.todayMinY = todayMinY
            self.rowSpacing = rowSpacing
        }
    }

    /// What a release would do now, and how the list shows it.
    public struct Drop: Equatable, Sendable {
        public var draggedID: UUID
        /// nil while the drop would leave the item where it is.
        public var target: Target?
        /// The insertion line's height in the list, and its folder depth (it starts at that
        /// depth's favicon); nil when the target draws no line (a combine, or an empty section).
        public var lineY: Double?
        public var lineDepth: Int = 0
        /// The rows on either side of the line.
        public var rowAbove: UUID?
        public var rowBelow: UUID?

        public init(draggedID: UUID, target: Target? = nil) {
            self.draggedID = draggedID
            self.target = target
        }

        public var isLink: Bool { draggedID == SidebarDropPlan.link }

        /// The row a combine would land on (its highlight), if any.
        public var combineRow: UUID? {
            switch target {
            case .split(let id, _)?, .into(let id)?: return id
            default: return nil
            }
        }
    }

    /// The stand-in for a dragged link, which has no row yet; no item has this id.
    public static let link = UUID()

    /// Where releasing `id` (or `link`) at `point` lands in `space`'s list. `group` is what moves
    /// along with it (picked tabs); `[id]` when nothing else is picked.
    @MainActor
    public static func resolve(dragged id: UUID, group: [UUID]? = nil, at point: (x: Double, y: Double),
                               layout: Layout, space spaceID: UUID, store: SidebarStore) -> Drop {
        guard let space = store.space(spaceID) else { return Drop(draggedID: id) }
        let group = group ?? [id]
        let items = layout.rows
        let isTab = store.item(id)?.isTab == true
        let combines = id != link
        let half = layout.rowSpacing / 2
        let p = point
        var target: Target?

        if let r = items.first(where: { p.y >= $0.minY - half && p.y < $0.maxY + half }), let item = store.item(r.itemID) {
            let rid = r.itemID
            let f = (p.y - r.minY) / max(1, r.maxY - r.minY)
            let middle = (0.25..<0.75).contains(f)
            let before = Target.insert(parent: r.parent, index: r.index)
            let after = Target.insert(parent: r.parent, index: r.index + 1)
            if group.contains(rid) || isInside(rid, id, store: store) {
                target = nil
            } else if item.isFolder {
                if f < 0.25 {
                    target = before
                } else if f >= 0.75 {
                    target = store.isExpanded(rid) ? .insert(parent: rid, index: 0) : after
                } else {
                    target = .into(rid)
                }
            } else if middle && isTab && item.isTab {
                // Arc combines two tabs into a split wherever the target sits (#191), in the
                // target's place: on a pinned tab it is a pinned split (#180).
                target = .split(with: rid, leading: p.x < r.midX)
            } else if middle && isTab && item.isSplit {
                target = .into(rid)
            } else if middle && !combines {
                // Arc 1.173.1 takes no link on a tab's middle.
                target = nil
            } else {
                target = f < 0.5 ? before : after
            }
        } else if p.y < (layout.pinnedMaxY + layout.todayMinY) / 2, !store.isBlank(space: spaceID) {
            // Between sections or past the last row: the divider splits pinned from Today.
            let count = store.item(space.pinnedContainerID)?.children.count ?? 0
            target = .insert(parent: space.pinnedContainerID, index: p.y < layout.pinnedMinY ? 0 : count)
        } else {
            // The New Tab row may lead Today, so its first tab, not the section, marks the top.
            let firstToday = items.first { $0.parent == space.todayContainerID }?.minY ?? layout.todayMinY
            let count = store.item(space.todayContainerID)?.children.count ?? 0
            target = .insert(parent: space.todayContainerID, index: p.y < firstToday ? 0 : count)
        }

        // Dropping next to itself, or a folder into itself, changes nothing.
        if case .insert(let parent, let index)? = target {
            if parent == id || isInside(parent, id, store: store) {
                target = nil
            } else if group.count == 1, store.item(id)?.parentID == parent, let old = store.item(parent)?.children.firstIndex(of: id),
                      index == old || index == old + 1 {
                target = nil
            }
        }

        // A live folder fills itself: nothing goes into it from outside, and its tabs make no new folders.
        switch target {
        case .into(let f)? where store.liveFolder(containing: f) != nil: target = nil
        case .insert(let parent, _)? where store.liveFolder(containing: parent) != nil && store.item(id)?.parentID != parent: target = nil
        case .split(let tab, _)? where store.liveFolder(containing: tab) != nil: target = nil
        default: break
        }

        var drop = Drop(draggedID: id, target: target)
        guard case .insert(let parent, let index)? = target else { return drop }
        let kids = store.item(parent)?.children ?? []
        var y: Double?
        if index < kids.count, let r = items.first(where: { $0.itemID == kids[index] }) {
            y = r.minY - half
        } else if index > 0, let r = items.last(where: { $0.itemID == kids[index - 1] || isInside($0.itemID, kids[index - 1], store: store) }) {
            y = r.maxY + half
        } else if store.item(parent)?.isFolder == true, let r = items.first(where: { $0.itemID == parent }) {
            y = r.maxY + half
        }
        // An empty section shows its own placeholder instead of a line.
        guard let y else { return drop }
        // A group's tabs sit at its header's depth (Arc doesn't indent them).
        drop.lineY = y
        drop.lineDepth = items.first { $0.itemID == parent }.map { $0.depth + (store.item(parent)?.isTabGroup == true ? 0 : 1) } ?? 0
        drop.rowAbove = items.last { $0.maxY <= y + 1 }?.itemID
        drop.rowBelow = items.first { $0.minY >= y - 1 }?.itemID
        return drop
    }

    /// Carries out `drop` in `window` (the Mac's `applyDrop` and what follows it): the item moves,
    /// combines or goes into its folder, and tabs dragged in from another window's list leave it.
    /// Returns whether anything changed.
    @MainActor @discardableResult
    public static func apply(_ drop: Drop, group: [UUID]? = nil, store: SidebarStore, window: UUID) -> Bool {
        let id = drop.draggedID
        guard !drop.isLink, store.item(id) != nil, let target = drop.target else { return false }
        let group = group ?? [id]
        switch target {
        case .insert(let parent, let index):
            store.moveItems(group, to: parent, index: index)
        case .split(let tab, let leading):
            // Arc opens the tab a drag picks up, so the new split ends up open on its pane (#180).
            if store.combineIntoSplit(id, onto: tab, leading: leading) != nil { store.selectTab(id, window: window) }
        case .into(let into):
            if store.item(into)?.isFolder == true {
                store.dropIntoFolder(group, folder: into)
            } else {
                store.moveItem(id, to: into, index: nil)
            }
        }
        for t in group where store.item(t)?.isTab == true { store.tookTab(t, into: window) }
        return true
    }

    /// Where a link let go on the list opens as a new tab: at the insertion point, or at the top
    /// of the folder it was let go on (which stays as it was, as a tab dropped there goes, #266).
    @MainActor
    public static func linkPlace(_ drop: Drop, store: SidebarStore) -> (parent: UUID, index: Int)? {
        switch drop.target {
        case .insert(let parent, let index)?: return (parent, index)
        case .into(let folder)? where store.item(folder)?.isFolder == true: return (folder, 0)
        default: return nil
        }
    }

    /// A link let go on the list opens there as a new tab, behind the page you're on (Arc 1.172.1, #419).
    @MainActor @discardableResult
    public static func dropLink(_ link: SidebarLinkDrop.Tab, drop: Drop, space: UUID, store: SidebarStore, window: UUID) -> SidebarItem? {
        guard let place = linkPlace(drop, store: store) else { return nil }
        return store.createTab(url: link.url, title: link.title, in: space, select: false, parent: place.parent, index: place.index, window: window)
    }

    // MARK: Favorites and spaces

    /// Whether `id` can go among `space`'s favorites (#176): a tab or a split from a list of the
    /// same kind of window (private or not), into a space that keeps favorites.
    @MainActor
    public static func favoritesAccept(_ id: UUID, space: UUID, store: SidebarStore) -> Bool {
        guard let item = store.item(id), item.isTab || item.isSplit else { return false }
        return store.isIncognito(item: id) == store.isIncognito(space: space) && !store.isBlank(space: space)
    }

    /// Lets go of `id` in slot `slot` of `space`'s favorite tiles (counted with the dragged one in
    /// its new place): a favorite moves there, anything else joins the favorites there (the Mac's
    /// SpaceColumnView.performDragOperation).
    @MainActor @discardableResult
    public static func dropOnFavorites(_ id: UUID, slot: Int, space spaceID: UUID, store: SidebarStore) -> Bool {
        guard favoritesAccept(id, space: spaceID, store: store), let space = store.space(spaceID) else { return false }
        let container = space.favoritesContainerID
        let children = store.item(container)?.children ?? []
        let order = store.children(of: container).filter { $0.isTab || $0.isSplit }.map(\.id)
        let resting = order.filter { $0 != id }
        let index = slot >= 0 && slot < resting.count ? (children.firstIndex(of: resting[slot]) ?? children.count) : children.count
        if order.contains(id) {
            store.moveItem(id, to: container, index: index)
        } else {
            store.addToFavorites(id, in: spaceID, at: index)
        }
        return true
    }

    /// Lets go of `id` on a space's icon: it moves to that space (the Mac's SpaceDockCell drop).
    @MainActor @discardableResult
    public static func dropOnSpace(_ id: UUID, group: [UUID]? = nil, space: UUID, store: SidebarStore) -> Bool {
        guard store.item(id) != nil, store.space(space) != nil, store.isIncognito(item: id) == store.isIncognito(space: space) else { return false }
        store.moveTabs(group ?? [id], toSpace: space)
        return true
    }

    /// How long a drag rests on another space's icon before that space comes forward, so the
    /// drop can go anywhere in its list (the Mac's SpaceDockCell, 0.5 s).
    public static let spaceHoverDelay: TimeInterval = 0.5

    /// A space icon dragged from cell `from` to cell `to` of `shown` (the icons as drawn, which
    /// can leave spaces out): where `moveSpace` puts it in the full order.
    @MainActor
    public static func spaceOrderIndex(moving id: UUID, toCell to: Int, shown: [UUID], store: SidebarStore) -> Int? {
        guard shown.indices.contains(to), shown[to] != id, store.spaceOrder.contains(id) else { return nil }
        return store.spaceOrder.firstIndex(of: shown[to])
    }

    // MARK: Helpers

    @MainActor
    static func isInside(_ id: UUID, _ ancestor: UUID, store: SidebarStore) -> Bool {
        var cur = store.item(id)?.parentID
        var hops = 0
        while let c = cur, hops < 64 {
            if c == ancestor { return true }
            cur = store.item(c)?.parentID
            hops += 1
        }
        return false
    }
}
