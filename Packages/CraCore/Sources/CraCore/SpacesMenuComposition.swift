import Foundation

/// The menu bar's list of Spaces. A row targets a Space by identity even though the customizable
/// shortcuts remain positional: Cra defines actions only for positions 1 through 9.
public struct SpacesMenuComposition: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let spaceID: UUID
        public let position: Int
        public let shortcutID: String?
    }

    public let navigation: [Row]

    /// The commands above the Space rows, in groups a separator apart: New Space, Edit Space,
    /// Change Profile and Delete Space, then Next and Previous Space.
    public static let commandsBefore: [[String]] = [
        ["newSpace", "editSpace", "changeProfile", "deleteSpace"],
        ["nextSpace", "previousSpace"],
    ]
    /// The commands below them, after a separator.
    public static let commandsAfter: [String] = ["manageSpaces"]

    /// Arc 1.172 keeps 24 characters of a long Space name before the ellipsis
    /// ("HomeHomeHomeHomeHomeHome…" in Spaces ▸, PR #481).
    public static let maximumNameLength = 24

    /// A Space's name as the menu shows it: the first 24 characters and an ellipsis when longer.
    public static func displayedName(_ name: String) -> String {
        name.count > maximumNameLength ? String(name.prefix(maximumNameLength)) + "…" : name
    }

    public init(spaceIDs: [UUID]) {
        navigation = spaceIDs.enumerated().map { offset, spaceID in
            let position = offset + 1
            return Row(spaceID: spaceID, position: position,
                       shortcutID: position <= 9 ? "space" + String(position) : nil)
        }
    }
}
