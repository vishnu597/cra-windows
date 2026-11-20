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
}
