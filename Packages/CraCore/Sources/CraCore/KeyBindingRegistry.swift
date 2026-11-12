import Foundation
import Observation

/// The menu an action sits in (the Mac's menu bar, the Shortcuts pane's groups).
public enum MenuSection: String, Codable, Sendable {
    case app, file, edit, view, tabs, spaces, archive, window, help, none
}

/// An app command. Arc keeps the same shape: identifier + name + default
/// shortcut + the phrases type-travel matches ("typeTravelTriggers").
public struct KeyAction: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let section: MenuSection
    public var shortcuts: [KeyChord]
    public var triggers: [String]
    public var inCommandBar: Bool
    /// The command bar row's glyph, where Arc gives the command its own (else ⌘).
    public var symbol: String?

    public init(id: String, name: String, section: MenuSection, shortcuts: [KeyChord], triggers: [String] = [],
                inCommandBar: Bool = true, symbol: String? = nil) {
        self.id = id
        self.name = name
        self.section = section
        self.shortcuts = shortcuts
        self.triggers = triggers
        self.inCommandBar = inCommandBar
        self.symbol = symbol
    }

    public var primary: KeyChord? { shortcuts.first }
}

public extension KeyChord {
    init(_ key: String, _ modifiers: Modifiers) {
        self.init(key: key, modifiers: modifiers.rawValue)
    }
}

extension Notification.Name {
    /// Posted when the user edits shortcuts; the Mac app rebuilds its menus.
    public static let craKeyBindingsChanged = Notification.Name("craKeyBindingsChanged")
}

/// The action table plus the user's overrides (keybindings.json, action id to shortcuts).
@MainActor
@Observable
public final class KeyBindingRegistry {
    public private(set) var actions: [KeyAction]
    @ObservationIgnored private let defaults: [KeyAction]
    @ObservationIgnored private var pluginActions: [KeyAction] = []
    @ObservationIgnored private let overridesFile: JSONStore<KeyBindingOverrides>
    /// Every override the file holds, also for actions this table lacks (the Mac's file read on
    /// Windows, an action a later version drops): saving keeps them. The shortcuts and who gets
    /// each one's keys (#374). Observed, so the Shortcuts pane's pop-up follows a pick.
    private var overrides: KeyBindingOverrides

    /// `defaults` is the platform's table (KeyBindingDefaults.mac or .windows).
    public init(defaults: [KeyAction], file: JSONStore<KeyBindingOverrides>) {
        self.defaults = defaults
        actions = defaults
        overridesFile = file
        overrides = file.load(or: { KeyBindingOverrides() })
        apply()
    }

    /// The platform's table with the plugins' commands after New Folder, before any override.
    private var defaultActions: [KeyAction] {
        var table = defaults
        let insertion = table.firstIndex(where: { $0.id == "newFolder" }).map { $0 + 1 } ?? table.count
        table.insert(contentsOf: pluginActions, at: insertion)
        return table
    }

    private func apply() {
        actions = defaultActions.map { a in
            var a = a
            if let o = overrides.shortcuts[a.id] { a.shortcuts = o }
            return a
        }
    }

    /// Commands supplied by installed live-folder plugins, immediately after New Folder.
    public func setPluginActions(_ actions: [KeyAction]) {
        guard pluginActions != actions else { return }
        pluginActions = actions
        apply()
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    /// A sync document changed the shortcut overrides on disk.
    public func reloadOverrides() {
        overrides = overridesFile.load(or: { KeyBindingOverrides() })
        apply()
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    public func action(_ id: String) -> KeyAction? { actions.first { $0.id == id } }

    /// The first action one of whose shortcuts is `chord`.
    public func action(matching chord: KeyChord) -> KeyAction? {
        let held = chord.keys.intersection(KeyChord.Modifiers.held)
        return actions.first { a in a.shortcuts.contains { $0.key == chord.key && $0.keys.intersection(.held) == held } }
    }

    public func setShortcuts(_ shortcuts: [KeyChord], for id: String) {
        overrides.shortcuts[id] = shortcuts
        overridesFile.save(overrides)
        apply()
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    public func isOverridden(_ id: String) -> Bool { overrides.shortcuts[id] != nil || overrides.priorities[id] != nil }

    /// Who gets the action's keys while a page wants them too (Settings ▸ Shortcuts, #374).
    public func priority(of id: String) -> ShortcutPriority { overrides.priority(for: id) }

    public func setPriority(_ priority: ShortcutPriority, for id: String) {
        let current = action(id)?.shortcuts ?? []
        let defaults = defaultActions.first { $0.id == id }?.shortcuts ?? []
        overrides.setPriority(priority, for: id, current: current, defaults: defaults)
        overridesFile.save(overrides)
    }

    /// Reset Shortcut to Default: the keys and who gets them.
    public func resetShortcuts(for id: String) {
        overrides.shortcuts[id] = nil
        overrides.priorities[id] = nil
        overridesFile.save(overrides)
        apply()
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    /// Settings ▸ Shortcuts ▸ Reset All Shortcuts.
    public func resetOverrides() {
        overrides = KeyBindingOverrides()
        overridesFile.saveNow(overrides)
        apply()
        NotificationCenter.default.post(name: .craKeyBindingsChanged, object: nil)
    }

    public func actions(in section: MenuSection) -> [KeyAction] { actions.filter { $0.section == section } }

    /// The other actions sharing `action`'s first shortcut.
    public func conflicts(of action: KeyAction) -> [KeyAction] {
        guard let s = action.primary else { return [] }
        return actions.filter { $0.id != action.id && $0.shortcuts.contains(s) }
    }

    /// What the command bar offers (SuggestionEngine), in menu order, with the user's shortcuts
    /// as the platform writes them (`\.display` on the Mac, `\.windowsDisplay` on Windows).
    public func barCommands(display: (KeyChord) -> String) -> [CommandBarCommand] {
        actions.filter(\.inCommandBar).map {
            CommandBarCommand(id: $0.id, name: $0.name, triggers: $0.triggers, symbol: $0.symbol, shortcut: $0.primary.map(display))
        }
    }
}

public extension KeyChord.Modifiers {
    /// The four keys a shortcut is made of; Caps Lock and the function-key bit don't count.
    static let held: KeyChord.Modifiers = [.shift, .control, .option, .command]
}

/// Settings ▸ Shortcuts' list: the menus in Dia's order, filtered by the search field and the
/// filter menu's two toggles.
public enum ShortcutsList {
    public struct Group: Equatable, Sendable {
        public let title: String
        public let actions: [KeyAction]

        public init(title: String, actions: [KeyAction]) {
            self.title = title
            self.actions = actions
        }
    }

    public static let sections: [(MenuSection, String)] = [
        (.app, "Cra"), (.file, "File"), (.edit, "Edit"), (.view, "View"), (.spaces, "Spaces"),
        (.tabs, "Tabs"), (.archive, "Archive"), (.window, "Window"),
    ]

    /// The groups to show; a menu with nothing left is left out.
    @MainActor
    public static func groups(in registry: KeyBindingRegistry, query: String, customizedOnly: Bool = false,
                              conflictingOnly: Bool = false) -> [Group] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return sections.compactMap { section, title in
            let acts = registry.actions(in: section).filter { a in
                (q.isEmpty || a.name.lowercased().contains(q))
                    && (!customizedOnly || registry.isOverridden(a.id))
                    && (!conflictingOnly || !registry.conflicts(of: a).isEmpty)
            }
            return acts.isEmpty ? nil : Group(title: title, actions: acts)
        }
    }

    /// The warning under the shortcut field, nil without a conflict.
    public static func conflictNote(_ conflicts: [KeyAction]) -> String? {
        guard !conflicts.isEmpty else { return nil }
        return (conflicts.count == 1 ? "This shortcut conflicts with another shortcut: " : "This shortcut conflicts with other shortcuts: ")
            + conflicts.map(\.name).joined(separator: ", ")
    }
}
