import CraCore
import Foundation
import WinSDK

/// The app's one key binding registry: Windows' table (KeyBindingDefaults.windows) with the
/// user's keys from keybindings.json in the data folder. Shortcuts, the command bar's rows and
/// Settings ▸ Shortcuts all read it.
@MainActor
enum WinKeyBindings {
    static let shared = KeyBindingRegistry(defaults: KeyBindingDefaults.windows,
                                           file: JSONStore("keybindings.json", in: WinPaths.supportDir))
}

/// Who gets a shortcut's press while a page has the keyboard (Settings ▸ Shortcuts' Prefer Cra, Use
/// Both, Prefer Websites, #374): one router for every window, as the Mac's AppDelegate keeps one.
@MainActor
enum WinShortcutRouting {
    static var router = ShortcutRouter()

    /// Seconds since Windows started: the presses' clock.
    static var now: TimeInterval { Double(GetTickCount64()) / 1000 }

    /// The action a press is the shortcut of, unless it types a character on the layout (AltGr).
    static func action(for key: KeyPress) -> KeyAction? {
        guard !WinKeyboard.typesCharacter(key),
              let chord = KeyChord(windowsVirtualKey: key.keyCode, control: key.control, shift: key.shift, alt: key.alt) else { return nil }
        return WinKeyBindings.shared.action(matching: chord)
    }

    /// Before the page: the action Cra runs now, nil when the page gets the press. `watch` runs for a
    /// Use Both first press, to be called back `UseBothPresses.answerTime` later.
    static func beforePage(_ key: KeyPress, watch: (KeyAction, TimeInterval) -> Void) -> KeyAction? {
        guard let action = action(for: key) else { return nil }
        let at = now
        switch router.beforePage(action.id, priority: WinKeyBindings.shared.priority(of: action.id), at: at, isRepeat: key.isRepeat) {
        case .take: return action
        case .pass: return nil
        case .passAndWatch:
            watch(action, at)
            return nil
        }
    }

    /// The page handed the press back: its action, which Cra runs now.
    static func pageLeft(_ key: KeyPress) -> KeyAction? {
        guard let action = action(for: key) else { return nil }
        router.pageLeft(action.id)
        return action
    }

    /// A watched Use Both press the page kept: the toast's text, and the next press is Cra's while it shows.
    static func keptText(_ action: KeyAction, pressedAt: TimeInterval) -> String? {
        guard router.pageKept(action.id, pressedAt: pressedAt, now: now, offerTime: ToastStyle.visibleFor) else { return nil }
        let keys = WinKeyBindings.shared.action(action.id)?.primary?.windowsDisplay ?? ""
        return ShortcutRouter.againText(keys: keys, actionName: action.name)
    }
}
