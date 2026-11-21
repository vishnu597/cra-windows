import CraCore
import Foundation
import Testing

/// Arc's Create a Space page against the store: the origin wears the draft's theme while the page
/// is up, Cancel puts it back, Create Space makes the space and shows it.
@MainActor
struct SpaceCreationFlowTests {
    private let theme = SpaceColorPresets.newSpaceTheme(index: 3)

    @Test
    func thePageOpensOnTheOriginsProfileWearingTheDraftsTheme() {
        let f = StoreFixture()
        let profile = f.store.createProfile(name: "Work", forSpaces: [f.space.id])
        let origin = f.space
        let window = f.store.activeWindowID
        let (draft, from) = f.store.beginSpaceCreation(window: window, theme: theme)
        #expect(from == origin.id)
        #expect(draft.profile == profile.id && draft.title.isEmpty && !draft.themeChosen)
        #expect(f.store.isMakingSpace(window: window))
        #expect(f.store.space(origin.id)?.theme == theme)
        #expect(f.store.selectedTabID(window: window) == nil)
    }

    @Test
    func cancelPutsTheOriginBack() {
        let f = StoreFixture()
        let before = f.space
        let count = f.store.spaceOrder.count
        let window = f.store.activeWindowID
        var (draft, origin) = f.store.beginSpaceCreation(window: window, theme: theme)
        draft.theme = SpaceColorPresets.newSpaceTheme(index: 5)
        f.store.previewSpaceCreation(draft, origin: origin)
        #expect(f.store.space(origin)?.theme == draft.theme)
        f.store.cancelSpaceCreation(origin: origin, window: window)
        #expect(f.store.space(origin)?.theme == before.theme)
        #expect(!f.store.isMakingSpace(window: window))
        #expect(f.store.spaceOrder.count == count)
    }

    @Test
    func createSpaceMakesItAndShowsIt() {
        let f = StoreFixture()
        let before = f.space
        let window = f.store.activeWindowID
        var (draft, origin) = f.store.beginSpaceCreation(window: window, theme: theme)
        #expect(f.store.finishSpaceCreation(draft, origin: origin, window: window) == nil)
        #expect(f.store.isMakingSpace(window: window))
        draft.title = "  Garden "
        draft.icon = .emoji("🌻")
        draft.searchEngine = "ddg"
        let id = f.store.finishSpaceCreation(draft, origin: origin, window: window)
        let made = id.flatMap { f.store.space($0) }
        #expect(made?.title == "Garden" && made?.emoji == "🌻" && made?.theme == theme && made?.searchEngine == "ddg")
        #expect(f.store.focusedSpaceID(window: window) == id)
        #expect(f.store.space(origin)?.theme == before.theme)
        #expect(!f.store.isMakingSpace(window: window))
        #expect(f.sound)
    }
}
