import Foundation

/// Settings ▸ Profiles ▸ Rebuild from Arc (GitHub #131): an import from before Cra kept Arc's
/// profiles left every space on Default. This finds the spaces to move back onto the profile
/// their Arc space is on, matched by name, since ids differ between the browsers.
public enum ArcProfileRebuild {
    public struct CraSpace: Equatable, Sendable {
        public var id: UUID
        public var title: String
        /// On Default and not incognito: the only spaces a rebuild moves. One already on a
        /// profile was put there by hand.
        public var movable: Bool

        public init(id: UUID, title: String, movable: Bool) {
            self.id = id
            self.title = title
            self.movable = movable
        }
    }

    public struct ArcSpace: Equatable, Sendable {
        public var title: String
        /// Arc's profile folder ("Profile 2"); nil for Default.
        public var folder: String?
        /// The profile's name in Arc.
        public var name: String

        public init(title: String, folder: String?, name: String) {
            self.title = title
            self.folder = folder
            self.name = name
        }
    }

    public struct Move: Equatable, Sendable {
        public var spaceID: UUID
        public var spaceTitle: String
        public var folder: String
        public var profileName: String

        public init(spaceID: UUID, spaceTitle: String, folder: String, profileName: String) {
            self.spaceID = spaceID
            self.spaceTitle = spaceTitle
            self.folder = folder
            self.profileName = profileName
        }
    }

    /// The Cra spaces to put on an Arc profile: a movable space whose name (any case) is one Arc
    /// space's, when that space is on a profile other than Default. A name Arc uses on more than
    /// one profile, or Cra on more than one space, says nothing about which is which: skipped.
    public static func moves(cra: [CraSpace], arc: [ArcSpace]) -> [Move] {
        let arcByTitle = Dictionary(grouping: arc) { $0.title.lowercased() }
        let craCount = Dictionary(grouping: cra) { $0.title.lowercased() }.mapValues(\.count)
        return cra.compactMap { space in
            let key = space.title.lowercased()
            guard space.movable, craCount[key] == 1, let matches = arcByTitle[key],
                  Set(matches.map(\.folder)).count == 1, let match = matches.first, let folder = match.folder else { return nil }
            return Move(spaceID: space.id, spaceTitle: space.title, folder: folder, profileName: match.name)
        }
    }

    // MARK: What it asks and says (the Mac's ArcProfileRebuilder, shared with Windows)

    public enum Platform: Sendable { case mac, windows }

    public static let unreadable = DialogPrompt(title: "Cra couldn't read Arc's spaces.",
                                                message: "Arc's sidebar file is missing or in a format this version doesn't know.")

    /// Run with no Arc on the computer (the command bar offers it anyway).
    public static let arcMissing = DialogPrompt(title: "Arc isn't installed",
                                                message: "Rebuild Profiles from Arc reads Arc's spaces and profiles, so it needs Arc on this computer.")

    public static let nothingToMove = DialogPrompt(title: "No spaces to move",
                                                   message: "Every space named like one of your Arc spaces is already on the right profile, or Arc has it on its Default profile.")

    /// The question before anything moves: each space and its Arc profile, then what comes with
    /// them. The Mac brings the profiles' extensions too and restarts at once; on Windows
    /// extensions load in every profile, and the sign-ins arrive at the next start.
    public static func confirmation(_ moves: [Move], on platform: Platform) -> DialogPrompt {
        let one = moves.count == 1
        let list = moves.map { "\($0.spaceTitle) → \($0.profileName)" }.joined(separator: "\n") + "\n\n"
        let kept = "Sign-ins and passwords you added in Cra since the import stay with Default."
        let message: String, button: String
        switch platform {
        case .mac:
            message = list + "Cra brings over the sign-ins, passwords and extensions these Arc profiles have, so the spaces work as they did in Arc. "
                + kept + " macOS asks for your password to unlock Arc's data, then Cra restarts."
            button = "Move and Restart"
        case .windows:
            message = list + "Cra brings over the sign-ins and passwords these Arc profiles have, so the spaces work as they did in Arc. "
                + kept + " They come in the next time Cra opens."
            button = "Move Spaces"
        }
        return DialogPrompt(title: "Move \(one ? "this space" : "these spaces") to \(one ? "its" : "their") Arc profile\(one ? "" : "s")?",
                            message: message, actions: [DialogAction(button), .cancel])
    }

    /// Arc's sign-ins couldn't be read (`reason` says why): move anyway?
    public static func withoutSignIns(_ reason: String) -> DialogPrompt {
        DialogPrompt(title: "Move the spaces without their sign-ins?",
                     message: "\(reason) The spaces would start signed out of every site. Cancel changes nothing.",
                     actions: [DialogAction("Move Without Sign-ins"), .cancel])
    }

    public static let signInsNotSaved = DialogPrompt(title: "Cra couldn't save Arc's sign-ins.",
                                                     message: "The spaces moved, but they start signed out.")

    /// Windows' word once the spaces moved (the Mac restarts instead): how many, and what the
    /// sign-in import says (`CredentialImportReport.summary`).
    public static func moved(_ count: Int, credentials: String?) -> DialogPrompt {
        DialogPrompt(title: count == 1 ? "1 space moved" : "\(count) spaces moved",
                     message: credentials ?? "They’re on their Arc profiles now.")
    }
}
