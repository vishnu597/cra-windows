import CraCore
import Foundation
import Testing

/// The Library's Spaces page (Manage Spaces…): its width and how a card is reordered.
@MainActor
struct SpacesManagerLayoutTests {
    /// Arc's page: three cards beside the 113 pt rail are 113 + 27 + 3 × 240 + 2 × 24 + 34 + 29 + 37.5.
    @Test func widthFitsTheCards() {
        #expect(SpacesManagerLayout.width(spaces: 3, rail: 113) == 1008.5)
        #expect(SpacesManagerLayout.width(spaces: 1, rail: 113) == 480.5)
        #expect(SpacesManagerLayout.width(spaces: 0, rail: 113) == 240.5)
        // The Library widens to it, leaving the page 56 pt in a narrow window.
        #expect(LibraryWidth.sidebar(spacesCards: SpacesManagerLayout.width(spaces: 3, rail: 113), window: 1600) == 1008.5)
        #expect(LibraryWidth.sidebar(spacesCards: SpacesManagerLayout.width(spaces: 3, rail: 113), window: 900) == 844)
    }

    /// An incognito or Blank Window's own space has no card.
    @Test func standaloneSpacesHaveNoCard() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(SpacesManagerLayout.spaces(order: [a, b, c], standalone: { $0 == b }) == [a, c])
    }

    /// A card let go lands where its centre is: under half a card and gap stays put.
    @Test func dropLandsWhereTheCentreIs() {
        let a = UUID(), b = UUID(), c = UUID()
        let order = [a, b, c]
        let pitch = SpacesManagerLayout.card + SpacesManagerLayout.gap
        #expect(SpacesManagerLayout.drop(a, dx: pitch * 0.4, shown: order, spaceOrder: order) == nil)
        #expect(SpacesManagerLayout.drop(a, dx: pitch * 0.6, shown: order, spaceOrder: order) == 1)
        #expect(SpacesManagerLayout.drop(a, dx: pitch * 5, shown: order, spaceOrder: order) == 2)
        #expect(SpacesManagerLayout.drop(c, dx: -pitch * 2, shown: order, spaceOrder: order) == 0)
        #expect(SpacesManagerLayout.drop(UUID(), dx: pitch, shown: order, spaceOrder: order) == nil)
    }

    /// Move Left and Move Right step one card, and not past the ends.
    @Test func moveStepsOneCard() {
        let a = UUID(), b = UUID(), c = UUID()
        let order = [a, b, c]
        #expect(SpacesManagerLayout.move(b, by: 1, shown: order, spaceOrder: order) == 2)
        #expect(SpacesManagerLayout.move(b, by: -1, shown: order, spaceOrder: order) == 0)
        #expect(SpacesManagerLayout.move(a, by: -1, shown: order, spaceOrder: order) == nil)
        #expect(SpacesManagerLayout.move(c, by: 1, shown: order, spaceOrder: order) == nil)
    }

    @Test func aDragUsesTheFixedViewportAndItsScrollOffset() {
        let drag = SpacesManagerLayout.Drag(pointerX: 500, scrollOffset: 100, index: 1, count: 4)
        #expect(drag.offset(pointerX: 600, scrollOffset: 100) == 100)
        // Moving the card itself changes neither the captured origin nor another sample.
        #expect(drag.offset(pointerX: 600, scrollOffset: 100) == 100)
        #expect(drag.offset(pointerX: 600, scrollOffset: 140) == 140)
        #expect(drag.offset(pointerX: 480, scrollOffset: 80) == -40)
    }

    @Test func aDragStopsAtTheActualFirstAndLastCard() {
        let pitch = SpacesManagerLayout.card + SpacesManagerLayout.gap
        let drag = SpacesManagerLayout.Drag(pointerX: 500, scrollOffset: 0, index: 1, count: 3)
        #expect(drag.offset(pointerX: -1000, scrollOffset: 0) == -pitch)
        #expect(drag.offset(pointerX: 2000, scrollOffset: 0) == pitch)
        let only = SpacesManagerLayout.Drag(pointerX: 100, scrollOffset: 0, index: 0, count: 1)
        #expect(only.offset(pointerX: 300, scrollOffset: 0) == 0)
    }

    /// The index goes to SidebarStore.moveSpace, which puts the space in the shown card's place.
    @Test func storeFollowsTheDrop() throws {
        let f = StoreFixture()
        let first = f.store.spaceOrder[0]
        let work = f.store.createSpace(title: "Work", emoji: "💼", focus: false).id
        let play = f.store.createSpace(title: "Play", emoji: "🎮", focus: false).id
        let pitch = SpacesManagerLayout.card + SpacesManagerLayout.gap
        let shown = SpacesManagerLayout.spaces(order: f.store.spaceOrder, standalone: { f.store.isStandalone(space: $0) })
        let to = try #require(SpacesManagerLayout.drop(first, dx: pitch * 2, shown: shown, spaceOrder: f.store.spaceOrder))
        f.store.moveSpace(first, to: to)
        #expect(f.store.spaceOrder == [work, play, first])
        let back = try #require(SpacesManagerLayout.move(first, by: -2, shown: f.store.spaceOrder, spaceOrder: f.store.spaceOrder))
        f.store.moveSpace(first, to: back)
        #expect(f.store.spaceOrder == [first, work, play])
    }

    /// Manage Spaces… is a Windows command with no key, as on the Mac, and a private window's
    /// command bar leaves it out (its window shows only its own space).
    @Test func manageSpacesIsAWindowsCommand() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        #expect(windows["manageSpaces"]?.shortcuts.isEmpty == true)
        #expect(windows["manageSpaces"]?.name == "Manage Spaces…")
        #expect(KeyBindingDefaults.hiddenInPrivateWindows.contains("manageSpaces"))
    }
}
