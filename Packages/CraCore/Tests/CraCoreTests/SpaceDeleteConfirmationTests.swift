import CraCore
import Testing

/// Delete Space… asks first, in Arc's words, and the last space can't go.
struct SpaceDeleteConfirmationTests {
    @Test
    func asksBeforeArchivingTheSpacesTabs() {
        let p = SpaceDeleteConfirmation.prompt(title: "Work", spaceCount: 3)
        #expect(p.canDelete)
        #expect(p.title == "Delete your “Work” Space?")
        #expect(p.message == "This will archive all the tabs and folders inside it.")
    }

    @Test
    func theLastSpaceStays() {
        let p = SpaceDeleteConfirmation.prompt(title: "Only", spaceCount: 1)
        #expect(!p.canDelete && p.message == nil && p.title == "You need at least one space.")
    }

    @Test
    func onlyTheRedDeleteDeletes() {
        let p = SpaceDeleteConfirmation.prompt(title: "Work", spaceCount: 2)
        #expect(p.actions.map(\.title) == ["Delete", "Cancel"])
        #expect(p.actions.first?.role == .destructive)
        #expect(p.deletes(picked: 0))
        #expect(!p.deletes(picked: 1) && !p.deletes(picked: nil))
    }

    @Test
    func theLastSpacesNoticeHasOnlyOK() {
        let p = SpaceDeleteConfirmation.prompt(title: "Only", spaceCount: 1)
        #expect(p.actions.map(\.title) == ["OK"])
        #expect(!p.deletes(picked: 0))
    }
}
