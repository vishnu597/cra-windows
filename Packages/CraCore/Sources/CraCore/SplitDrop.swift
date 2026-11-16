// CGFloat comes from Foundation off Apple platforms (Windows, Linux).
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Letting go of a sidebar tab, or a page's link, where `SplitDropProposal` proposed a split: the
/// Mac's `PageSplitDrop.drop`, shared so Windows' window lands the same drops.
public enum SplitDrop {
    public enum Payload: Equatable, Sendable {
        case tab(UUID)
        case link(SidebarLinkDrop.Tab)

        public var isLink: Bool { if case .link = self { true } else { false } }
    }

    /// Puts the tab or link in the window's split at `target` (a new split with the page shown
    /// when there is one page) and opens it; a replaced pane goes back to the sidebar, right after
    /// the split. `panes` are the panes on screen, in order. Returns the new pane, nil when
    /// nothing changed.
    @MainActor @discardableResult
    public static func drop(_ payload: Payload, at target: SplitDropProposal.Target, panes: [UUID], splitOrientation: SplitOrientation,
                            store: SidebarStore, window: UUID?) -> UUID? {
        guard let anchor = panes.first else { return nil }
        let insert: SplitDropProposal.Insert
        var replaced: UUID?
        switch target {
        case .insert(let i):
            guard panes.count < SplitDropProposal.maximumPanes else { return nil }
            insert = i
        case .replace(let index):
            guard panes.indices.contains(index), panes.count > 1 else { return nil }
            insert = .init(index: index, orientation: splitOrientation)
            replaced = panes[index]
        }
        let index = min(max(0, insert.index), panes.count)
        let pane: UUID
        switch payload {
        case .tab(let id):
            guard !panes.contains(id), store.item(id)?.isTab == true else { return nil }
            if let split = store.splitContaining(anchor) {
                store.addToSplit(split.id, tabID: id, at: index)
                guard let s = store.splitContaining(anchor), let p = store.paneID(for: id, in: s) else { return nil }
                pane = p
            } else {
                var order = panes
                order.insert(id, at: index)
                guard let s = store.createSplit(with: order, at: anchor), let p = store.paneID(for: id, in: s) else { return nil }
                pane = p
            }
        case .link(let link):
            let ref = index < panes.count ? panes[index] : panes[panes.count - 1]
            guard let tab = store.addEmptyPane(nextTo: ref, after: index >= panes.count, url: link.url, title: link.title, window: window) else { return nil }
            pane = tab.id
        }
        guard let split = store.splitContaining(pane) else { return nil }
        let others = (store.item(split.id)?.children ?? []).filter { $0 != pane }
        var factors = SplitPaneLayout.normalizedFactors(ids: others, stored: split.split?.widthFactors ?? [:])
        if let replaced {
            store.separateFromSplit(replaced)
            // The page takes the replaced pane's share.
            factors[pane] = factors.removeValue(forKey: replaced)
            store.setSplitWidthFactors(split.id, factors.mapValues(Double.init))
        } else {
            if split.split?.orientation != insert.orientation { store.flipSplitOrientation(split.id) }
            // The others keep their proportions and make room, as the region showed.
            let shares = SplitDropProposal.panes(others.map { SplitPaneLayout.Pane(id: $0, factor: factors[$0] ?? 0) }, inserting: pane, at: insert)
            store.setSplitWidthFactors(split.id, Dictionary(uniqueKeysWithValues: shares.map { ($0.id, Double($0.factor)) }))
        }
        store.selectTab(pane, window: window)
        return pane
    }

    /// What the window shows while a sidebar tab is dragged over its panes.
    public enum Showing: Equatable, Sendable {
        /// The panes on screen take the drag as they are.
        case asIs
        /// The press on the tab opened it, so it is the page on screen: Arc shows the tab from
        /// before the press again and splits with that.
        case swap(to: UUID)
        /// The dragged tab is already one of the panes: nothing to split with.
        case refused
    }

    /// The Mac's PageSplitDrop rule for a tab `id` dragged over `panes`, `before` the tab open
    /// before the press.
    @MainActor
    public static func showing(dragging id: UUID, panes: [UUID], before: UUID?, store: SidebarStore) -> Showing {
        guard panes.contains(id) else { return .asIs }
        guard let before, before != id, store.item(before)?.isTab == true, !store.paneTabIDs(for: before).contains(id), panes == [id]
        else { return .refused }
        return .swap(to: before)
    }
}
