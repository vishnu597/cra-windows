import CraCore
import Foundation
import Testing

struct ArcProfileRebuildPromptTests {
    private let moves = [
        ArcProfileRebuild.Move(spaceID: UUID(), spaceTitle: "Work", folder: "Profile 1", profileName: "Work Profile"),
        ArcProfileRebuild.Move(spaceID: UUID(), spaceTitle: "School", folder: "Profile 2", profileName: "Uni"),
    ]

    @Test func macConfirmationListsTheMovesAndRestarts() {
        let prompt = ArcProfileRebuild.confirmation(moves, on: .mac)
        #expect(prompt.title == "Move these spaces to their Arc profiles?")
        #expect(prompt.message.hasPrefix("Work → Work Profile\nSchool → Uni\n\n"))
        #expect(prompt.message.contains("sign-ins, passwords and extensions"))
        #expect(prompt.message.hasSuffix("macOS asks for your password to unlock Arc's data, then Cra restarts."))
        #expect(prompt.actions == [DialogAction("Move and Restart"), .cancel])
    }

    /// Windows has no restart and loads extensions in every profile: it says what it does.
    @Test func windowsConfirmationSaysSignInsComeAtTheNextStart() {
        let prompt = ArcProfileRebuild.confirmation(Array(moves.prefix(1)), on: .windows)
        #expect(prompt.title == "Move this space to its Arc profile?")
        #expect(prompt.message.hasPrefix("Work → Work Profile\n\n"))
        #expect(!prompt.message.contains("extensions"))
        #expect(!prompt.message.contains("macOS"))
        #expect(prompt.message.hasSuffix("They come in the next time Cra opens."))
        #expect(prompt.actions == [DialogAction("Move Spaces"), .cancel])
    }

    @Test func theOtherSheets() {
        #expect(ArcProfileRebuild.unreadable.actions == [DialogAction("OK")])
        #expect(ArcProfileRebuild.nothingToMove.title == "No spaces to move")
        // PC test, 22 Nov 2026: without Arc the command said it couldn't read Arc's spaces.
        #expect(ArcProfileRebuild.arcMissing.title == "Arc isn't installed")
        #expect(ArcProfileRebuild.arcMissing.actions == [DialogAction("OK")])
        let without = ArcProfileRebuild.withoutSignIns("Arc's key is locked.")
        #expect(without.message == "Arc's key is locked. The spaces would start signed out of every site. Cancel changes nothing.")
        #expect(without.actions.first == DialogAction("Move Without Sign-ins"))
        #expect(ArcProfileRebuild.signInsNotSaved.message == "The spaces moved, but they start signed out.")
        #expect(ArcProfileRebuild.moved(1, credentials: nil).title == "1 space moved")
        #expect(ArcProfileRebuild.moved(3, credentials: "4 passwords come in the next time Cra opens.").message
                == "4 passwords come in the next time Cra opens.")
        #expect(ArcProfileRebuild.moved(2, credentials: nil).message == "They’re on their Arc profiles now.")
    }

    /// The command bar's Rebuild Profiles from Arc… on Windows: no keys, worded for what Windows brings.
    @Test func windowsListsTheCommand() {
        let action = KeyBindingDefaults.windows.first { $0.id == "rebuildArcProfiles" }
        #expect(action?.name == "Rebuild Profiles from Arc…")
        #expect(action?.shortcuts.isEmpty == true)
        let text = KeyBindingDefaults.windowsText["rebuildArcProfiles"]
        #expect(text?.description.contains("extensions") == false)
    }
}
