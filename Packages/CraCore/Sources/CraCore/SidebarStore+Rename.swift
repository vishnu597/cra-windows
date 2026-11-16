import Foundation

extension SidebarStore {
    /// Rename Space…, as the Mac's space header field commits it (SpaceColumnView.endRename) and
    /// the Windows sidebar's: the name trimmed; an empty name, or the one it has, changes nothing.
    /// Returns whether the space took the name.
    @discardableResult
    public func renameSpace(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var space = space(id), !trimmed.isEmpty, trimmed != space.title else { return false }
        space.title = trimmed
        updateSpace(space)
        return true
    }
}
