import Foundation

/// Arc's Create a Space page against the store (the Mac's MainWindowController
/// beginSpaceCreation, cancelSpaceCreation and finishSpaceCreation, which Windows shares). While
/// the page is up the space it was opened on wears the draft's theme, the way a space wears the
/// theme its editor is trying, and the window shows no tab; nothing else changes until Create Space.
extension SidebarStore {
    /// Opens the page in `window` on its focused space, the origin: a draft on `theme` and on the
    /// origin's profile, as Arc starts it.
    public func beginSpaceCreation(window: UUID?, theme: SpaceTheme = SpaceColorPresets.newSpaceTheme()) -> (draft: SpaceCreationDraft, origin: UUID) {
        let origin = focusedSpaceID(window: window)
        let draft = SpaceCreationDraft(theme: theme, profile: SpaceProfiles.forNewSpace(from: space(origin), profiles: profiles))
        previewTheme(draft.theme, forSpace: origin)
        windowsMakingSpace.insert(window ?? activeWindowID)
        return (draft, origin)
    }

    /// The draft's theme changed (Choose a Theme): the origin wears it.
    public func previewSpaceCreation(_ draft: SpaceCreationDraft, origin: UUID) {
        previewTheme(draft.theme, forSpace: origin)
    }

    /// Cancel, Escape, or another space picked: the origin comes back as it was.
    public func cancelSpaceCreation(origin: UUID, window: UUID?) {
        endThemePreview(forSpace: origin, keep: false)
        windowsMakingSpace.remove(window ?? activeWindowID)
    }

    /// Create Space: the space is made on the draft's name, icon, theme, profile and search engine
    /// and shown in `window`; nil (and the page stays) while the name is empty.
    @discardableResult
    public func finishSpaceCreation(_ draft: SpaceCreationDraft, origin: UUID, window: UUID?) -> UUID? {
        guard draft.canCreate else { return nil }
        endThemePreview(forSpace: origin, keep: false)
        let id = createSpace(title: draft.createdTitle, emoji: draft.icon.emoji, symbol: draft.icon.symbol,
                             iconImage: draft.icon.image, theme: draft.theme, focus: false).id
        if let profile = draft.profile { setProfile(profile, forSpace: id) }
        setSearchEngine(draft.searchEngine, forSpace: id)
        focusSpace(id, window: window)
        windowsMakingSpace.remove(window ?? activeWindowID)
        return id
    }
}
