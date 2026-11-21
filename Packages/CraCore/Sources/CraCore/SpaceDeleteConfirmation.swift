import Foundation

/// Arc's question before Delete Space… (the Mac's AppDelegate.confirmDeleteSpace): the last space
/// can't go, and any other asks first because its tabs and folders are archived.
public struct SpaceDeleteConfirmation: Equatable, Sendable {
    public var title: String
    public var message: String?
    /// False for the last space: the dialog only says so, with no Delete.
    public var canDelete: Bool

    public init(title: String, message: String?, canDelete: Bool) {
        self.title = title
        self.message = message
        self.canDelete = canDelete
    }

    /// What to ask before deleting the space named `title`, with `spaceCount` spaces in all.
    public static func prompt(title: String, spaceCount: Int) -> SpaceDeleteConfirmation {
        guard spaceCount > 1 else { return .init(title: "You need at least one space.", message: nil, canDelete: false) }
        return .init(title: "Delete your “\(title)” Space?", message: "This will archive all the tabs and folders inside it.", canDelete: true)
    }
}
