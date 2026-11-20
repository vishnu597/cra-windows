import Foundation

/// The rows of Arc's sidebar + creation menu (Arc 1.172.1, the Mac's SpaceDockView
/// .toggleCreationMenu), in order, each with the command it runs and whether it can run now.
public enum SidebarCreationEntries {
    public struct Entry: Equatable, Sendable {
        /// The command (KeyBindingDefaults) the row runs; its keys come from that binding.
        public let action: String
        public let title: String
        /// An SF Symbols name.
        public let symbol: String
        public let enabled: Bool

        public init(action: String, title: String, symbol: String, enabled: Bool) {
            self.action = action
            self.title = title
            self.symbol = symbol
            self.enabled = enabled
        }
    }

    /// `selectedURL`: the open tab's address, nil without one; New Boost needs a web page with a
    /// host. `selectedPanes`: how many panes the open tab's split has (1 for a lone tab, nil without
    /// an open tab); New Split needs room for one more under `paneLimit`.
    public static func entries(selectedURL: String?, selectedPanes: Int?, paneLimit: Int) -> [Entry] {
        let url = selectedURL.flatMap(URL.init(string:))
        let canBoost = ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && !(url?.host ?? "").isEmpty
        let canSplit = selectedPanes.map { $0 < paneLimit } ?? false
        return [
            Entry(action: "newSpace", title: "New Space", symbol: "plus.rectangle.on.rectangle", enabled: true),
            Entry(action: "newFolder", title: "New Folder", symbol: "folder", enabled: true),
            Entry(action: "newEasel", title: "New Easel", symbol: "scribble", enabled: true),
            Entry(action: "newBoost", title: "New Boost", symbol: "paintbrush.pointed", enabled: canBoost),
            Entry(action: "addSplitView", title: "New Split", symbol: "rectangle.split.2x1", enabled: canSplit),
            Entry(action: "newTab", title: "New Tab", symbol: "plus.rectangle", enabled: true),
        ]
    }
}
