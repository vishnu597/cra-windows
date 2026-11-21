import CraCore
import Testing

/// "Quit Cra?" and "Downloads in progress" (#272, #426) as Windows asks them.
struct QuitDialogTests {
    @Test func quitCraOffersQuitCancelAndStopAsking() throws {
        let dialog = try #require(QuitDialog.asking(.confirmQuit))
        #expect(dialog.title == "Quit Cra?")
        #expect(dialog.message == nil)
        #expect(dialog.buttons.map(\.title) == ["Quit", "Cancel", "Quit, and don’t ask again"])
        #expect(dialog.buttons.filter(\.isDefault).map(\.answer) == [.quit], "Return quits")
    }

    @Test func downloadsInProgressSaysTheyAreCancelled() throws {
        let dialog = try #require(QuitDialog.asking(.downloadsInProgress))
        #expect(dialog.title == "Downloads in progress")
        #expect(dialog.message?.contains("cancel") == true)
        #expect(dialog.buttons.map(\.answer) == [.quit, .stay])
        #expect(dialog.buttons.first?.title == "Close Cra")
    }

    @Test func nothingToAskIsNoDialog() {
        #expect(QuitDialog.asking(.none) == nil)
        #expect(QuitDialog.asking(QuitPrompt.on(source: .relaunch, downloadsRunning: true, warnBeforeQuitting: true)) == nil,
                "a restart asks nothing")
    }

    @Test func answers() {
        var warn = true
        let quits = QuitDialog.apply(.quit, warnBeforeQuitting: &warn)
        #expect(quits)
        #expect(warn)
        let stays = QuitDialog.apply(.stay, warnBeforeQuitting: &warn)
        #expect(!stays)
        #expect(warn)
        let escape = QuitDialog.apply(QuitDialog.dismissed, warnBeforeQuitting: &warn)
        #expect(!escape, "Escape stays")
        let stopAsking = QuitDialog.apply(.quitAndStopAsking, warnBeforeQuitting: &warn)
        #expect(stopAsking)
        #expect(!warn, "Quit, and don’t ask again turns Warn before quitting off")
    }

    @Test func sheetDrawsArcsQuitLayout() throws {
        let quit = try #require(QuitDialog.asking(.confirmQuit))
        let sheet = DialogActions(quit.actions)
        #expect(quit.actions.map(\.role) == [.primary, .cancel, .secondary])
        #expect(sheet.key(at: 0) == "↩", "Return quits")
        #expect(sheet.key(at: 1) == "ESC", "Escape cancels")
        #expect(sheet.leadingOrder == [2], "don’t ask again sits at the left edge, as in Arc")
        #expect(sheet.trailingOrder == [1, 0], "Cancel, then Quit last")
        #expect(quit.answer(picked: 0) == .quit)
        #expect(quit.answer(picked: 1) == .stay)
        #expect(quit.answer(picked: 2) == .quitAndStopAsking)
        #expect(quit.answer(picked: nil) == QuitDialog.dismissed, "Alt+F4 on the card stays")
        #expect(quit.answer(picked: 9) == QuitDialog.dismissed)

        let downloads = try #require(QuitDialog.asking(.downloadsInProgress))
        let downloadsSheet = DialogActions(downloads.actions)
        #expect(downloadsSheet.trailingOrder == [1, 0], "Keep browsing, then Close Cra")
        #expect(downloadsSheet.leadingOrder.isEmpty)
        #expect(downloadsSheet.key(at: 1) == "ESC")
    }

    @Test func oneQuestionAtATime() {
        var requests = QuitRequests()
        let first = requests.begin()
        #expect(first == .new)
        let second = requests.begin()
        #expect(second == .asking, "a second Alt+F4 while asking doesn't ask again")
        requests.answered(quit: false)
        let afterCancel = requests.begin()
        #expect(afterCancel == .new, "after Cancel the next close asks again")
        requests.answered(quit: true)
        let quitting = requests.begin()
        #expect(quitting == .quitting)
    }
}
