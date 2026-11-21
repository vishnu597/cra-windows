import Foundation

/// What quitting asks (`QuitPrompt`), in the Mac's words (AppDelegate's confirmQuit and
/// confirmQuitCancellingDownloads): the Windows app draws its own card from it.
public struct QuitDialog: Equatable, Sendable {
    public enum Answer: Equatable, Sendable {
        case quit
        /// Quit, and turn Warn before quitting off.
        case quitAndStopAsking
        case stay
    }

    public struct Button: Equatable, Sendable {
        public var title: String
        public var answer: Answer
        /// The one Return presses.
        public var isDefault: Bool

        public init(_ title: String, _ answer: Answer, isDefault: Bool = false) {
            (self.title, self.answer, self.isDefault) = (title, answer, isDefault)
        }
    }

    public var title: String
    public var message: String?
    /// In reading order: the default one first, as the Mac's alert lists them.
    public var buttons: [Button]

    /// The question for `prompt`; nil when quitting asks nothing.
    public static func asking(_ prompt: QuitPrompt) -> QuitDialog? {
        switch prompt {
        case .none: return nil
        case .confirmQuit:
            return QuitDialog(title: "Quit Cra?", message: nil,
                              buttons: [Button("Quit", .quit, isDefault: true), Button("Cancel", .stay),
                                        Button("Quit, and don’t ask again", .quitAndStopAsking)])
        case .downloadsInProgress:
            return QuitDialog(title: "Downloads in progress",
                              message: "There are downloads in progress. Closing the application will cancel them.",
                              buttons: [Button("Close Cra", .quit, isDefault: true), Button("Keep browsing", .stay)])
        }
    }

    /// The buttons as Arc's dialog sheet draws them (`DialogActions`): the default one primary,
    /// staying the cancel one, "Quit, and don’t ask again" secondary at the card's left edge.
    public var actions: [DialogAction] {
        buttons.map { button in
            let role: DialogAction.Role = button.isDefault ? .primary
                : button.answer == .stay ? .cancel : .secondary
            return DialogAction(button.title, role: role)
        }
    }

    /// The answer for the sheet's pick: its button's, or `dismissed` when it went without one.
    public func answer(picked index: Int?) -> Answer {
        guard let index, buttons.indices.contains(index) else { return Self.dismissed }
        return buttons[index].answer
    }

    /// Escape and closing the card: stay.
    public static let dismissed = Answer.stay

    /// Whether the answer quits, and what it does to Warn before quitting.
    public static func apply(_ answer: Answer, warnBeforeQuitting: inout Bool) -> Bool {
        switch answer {
        case .quit: return true
        case .quitAndStopAsking:
            warnBeforeQuitting = false
            return true
        case .stay: return false
        }
    }
}
