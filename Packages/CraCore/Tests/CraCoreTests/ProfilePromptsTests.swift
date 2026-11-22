import CraCore
import Testing

struct ProfilePromptsTests {
    @Test func renameStartsWithTheNameAndSaveWaitsForOne() {
        let prompt = ProfilePrompts.rename(current: "Work")
        #expect(prompt.title == "Rename your Profile")
        #expect(prompt.input == "Work")
        #expect(prompt.placeholder == "Profile name")
        let actions = DialogActions(prompt.actions)
        #expect(actions.buttons[actions.defaultIndex!].title == "Save")
        #expect(actions.isEnabled(at: 0, input: "Work", requiresInput: prompt.requiresInput))
        #expect(!actions.isEnabled(at: 0, input: "  ", requiresInput: prompt.requiresInput))
        #expect(actions.isEnabled(at: 1, input: "", requiresInput: prompt.requiresInput))
        #expect(prompt.accepted("Home") == "Home")
        #expect(prompt.accepted(" \n") == nil)
        #expect(prompt.accepted(nil) == nil)
    }

    @Test func deleteNamesTheProfileAndIsDestructive() {
        let prompt = ProfilePrompts.delete(name: "Work")
        #expect(prompt.title == "Delete “Work”?")
        #expect(prompt.actions.first == DialogAction("Delete Profile", role: .destructive))
        #expect(prompt.input == nil)
        #expect(prompt.suppressionTitle == nil)
        #expect(DialogActions(prompt.actions).cancelIndex == 1)
    }

    @Test func littleWindowProfileChangeOffersDontAskAgain() {
        let prompt = ProfilePrompts.changeLittleWindowProfile(to: "Personal")
        #expect(prompt.title == "Open this page in Personal?")
        #expect(prompt.actions == [DialogAction("Change Profile"), .cancel])
        #expect(prompt.suppressionTitle == "Don’t ask again")
        #expect(ProfilePrompts.littleWindowBypassKey == "shouldBypassConfirmLittleWindowProfileDialog")
        // Without a field, what's typed doesn't matter.
        #expect(prompt.accepted("") == "")
    }
}
