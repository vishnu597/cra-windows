import Foundation

/// Sidebar items in arrival order, with folders created where their first tab appears: for
/// browsers that store each tab with the folders it sits in (Zen, Ardia, Yab) rather than a tree.
/// A folder is known by its id; the same URL twice in one folder comes over once.
public final class ImportTree {
    private final class Node {
        var item: ImportedItem
        var kids: [Node] = []
        var folders: [String: Node] = [:]
        init(_ item: ImportedItem) { self.item = item }
        var built: ImportedItem { var it = item; if it.isFolder { it.children = kids.map(\.built) }; return it }
    }
    private let root = Node(ImportedItem(url: nil, isFolder: true))

    public init() {}

    /// `path` runs from the outermost folder to the one the item is in.
    public func insert(_ item: ImportedItem, path: [(id: String, name: String)]) {
        var n = root
        for (id, name) in path {
            if let f = n.folders[id] { n = f; continue }
            let f = Node(ImportedItem(customTitle: name, pageTitle: name, url: nil, isFolder: true))
            n.kids.append(f)
            n.folders[id] = f
            n = f
        }
        if !n.kids.contains(where: { !$0.item.isFolder && $0.item.url == item.url }) { n.kids.append(Node(item)) }
    }

    public var items: [ImportedItem] { root.kids.map(\.built) }
}
