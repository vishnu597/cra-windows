import Foundation

/// What a Blank Window (`BlankWindow`, #220) shows and runs, as the Mac decides it in
/// SpaceColumnView, SpaceListView, SidebarView and AppDelegate.validateMenuItem: its sidebar is
/// "This Window" over its tabs, with "Move to…" in the header, and none of a space's parts.
public enum BlankWindowChrome {
    /// The parts of a sidebar a window shows.
    public struct Sidebar: Equatable, Sendable {
        /// The favorites grid, the pinned section and the line under it.
        public var favorites: Bool, pinned: Bool, divider: Bool
        /// The space icons and + at the bottom (Arc 1.172: a Blank Window's + does nothing).
        public var spaceDock: Bool, plus: Bool
        /// A click or double-click on the header folds pinned tabs or renames the space.
        public var headerActs: Bool
        /// "Move to…" at the header's end.
        public var moveTo: Bool
    }

    public static func sidebar(blank: Bool) -> Sidebar {
        Sidebar(favorites: !blank, pinned: !blank, divider: !blank, spaceDock: !blank, plus: !blank, headerActs: !blank, moveTo: blank)
    }

    /// Commands that act on a space's own parts, which a Blank Window has none of: its space
    /// is no space of the list (edit, delete, page, manage, profile), and it has no pinned section
    /// or favorites to put a tab in.
    public static let offCommands: Set<String> = [
        "collapsePinned", "resetSpaceTabs", "editSpace", "deleteSpace", "nextSpace", "previousSpace", "manageSpaces",
        "changeProfile", "pinTab", "favoriteTab", "newFolder", "resetTab",
    ]

    public static func runs(_ id: String, blank: Bool) -> Bool { !blank || !offCommands.contains(id) }

    /// "Move to…": the spaces in the sidebar's order, none that only its own window shows.
    public static func moveTargets(_ spaces: [Space], standalone: (UUID) -> Bool) -> [Space] {
        spaces.filter { !standalone($0.id) }
    }
}
