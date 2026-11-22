import Foundation

/// What one of Arc's dialog sheets says and asks for, for an app that draws the card itself (the
/// Mac's AppDialog takes the same fields): its title and message, its buttons, the text field's
/// starting value (nil for none) and placeholder, whether the default button waits for text, and
/// the "Don’t ask again" box's title (nil for none).
public struct DialogPrompt: Equatable, Sendable {
    public var title: String
    public var message: String
    public var actions: [DialogAction]
    public var input: String?
    public var placeholder: String
    public var requiresInput: Bool
    public var suppressionTitle: String?

    public init(title: String, message: String = "", actions: [DialogAction] = [DialogAction("OK")],
                input: String? = nil, placeholder: String = "", requiresInput: Bool = false, suppressionTitle: String? = nil) {
        self.title = title
        self.message = message
        self.actions = actions
        self.input = input
        self.placeholder = placeholder
        self.requiresInput = requiresInput
        self.suppressionTitle = suppressionTitle
    }

    /// The text the default button keeps: what was typed, or nil while the field is blank and
    /// the button waits for text (`DialogActions.isEnabled`).
    public func accepted(_ typed: String?) -> String? {
        guard let typed else { return nil }
        if requiresInput, typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return typed
    }
}

/// Arc's profile sheets, word for word (ProfilesPane and LittleWindowController on the Mac).
public enum ProfilePrompts {
    /// Settings ▸ Profiles ▸ Rename: the name in a field, Save waiting for one.
    public static func rename(current: String) -> DialogPrompt {
        DialogPrompt(title: "Rename your Profile",
                     message: "This won’t affect the names of any of the Spaces associated with this Profile.",
                     actions: [DialogAction("Save"), .cancel], input: current, placeholder: "Profile name", requiresInput: true)
    }

    /// Settings ▸ Profiles ▸ Delete: only a profile no space uses gets here.
    public static func delete(name: String) -> DialogPrompt {
        DialogPrompt(title: "Delete “\(name)”?",
                     message: "Deleting this Profile will permanently remove any cookies, history, preferences, and logins that belong to it.",
                     actions: [DialogAction("Delete Profile", role: .destructive), .cancel])
    }

    /// A Little Window's profile chip (Arc's ProfileDialogUtils, changeProfileInLittleWindow): a
    /// page can't move between profiles, so it loads again in the other one.
    public static func changeLittleWindowProfile(to name: String) -> DialogPrompt {
        DialogPrompt(title: "Open this page in \(name)?",
                     message: "Each Profile has different browser data, so this webpage might look a little different.",
                     actions: [DialogAction("Change Profile"), .cancel], suppressionTitle: "Don’t ask again")
    }

    /// Arc's preference that "Don’t ask again" sets (shouldBypassConfirmLittleBrowserProfileDialog).
    public static let littleWindowBypassKey = "shouldBypassConfirmLittleWindowProfileDialog"
}
