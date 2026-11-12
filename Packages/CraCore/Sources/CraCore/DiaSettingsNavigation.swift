import Foundation
import Observation

/// The panes in Dia's Settings sidebar (Dia 1.54.2: Account, Tabs, Privacy, Profiles, Skills,
/// Apps, Shortcuts, Advanced). Cra has no account or AI skills/apps; General
/// (system integration) and Extensions take rows instead. Each app draws the panes it has
/// (Windows `windowsPanes` so far) and gives them its own glyphs. The Mac moved to Arc 1.172.2's
/// tab toolbar (`SettingsTab`, upstream #372); Windows keeps this sidebar window until it follows.
public enum DiaSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general, tabs, links, max, privacy, profiles, extensions, plugins, shortcuts, performance, advanced
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .tabs: return "Tabs"
        case .links: return "Links"
        case .max: return "Max"
        case .privacy: return "Privacy"
        case .profiles: return "Profiles"
        case .plugins: return "Plugins"
        case .extensions: return "Extensions"
        case .shortcuts: return "Shortcuts"
        case .performance: return "Performance"
        case .advanced: return "Advanced"
        }
    }

    /// What the Windows app's Settings window lists: the panes whose features it has, in the
    /// Mac's order. More join as the port gets them (docs/windows.md).
    public static let windowsPanes: [DiaSettingsPane] = [.general, .tabs, .profiles, .shortcuts]
}

/// Selected pane plus the back/forward history behind the toolbar pill.
@MainActor
@Observable
public final class DiaSettingsNavigation {
    public private(set) var pane: DiaSettingsPane
    public private(set) var back: [DiaSettingsPane] = []
    public private(set) var forward: [DiaSettingsPane] = []
    /// The window is on screen: panes that refresh (Performance) stop while it is closed or covered.
    public var isOpen = false
    /// Counts each time Settings is brought up: panes showing what changed elsewhere (a profile's
    /// languages, set on Chromium's page) read it again.
    public private(set) var shown = 0
    public func didShow() { shown += 1 }

    public init(pane: DiaSettingsPane = .general) {
        self.pane = pane
    }

    public func show(_ p: DiaSettingsPane) {
        guard p != pane else { return }
        back.append(pane)
        forward = []
        pane = p
    }

    public func goBack() {
        guard let p = back.popLast() else { return }
        forward.append(pane)
        pane = p
    }

    public func goForward() {
        guard let p = forward.popLast() else { return }
        back.append(pane)
        pane = p
    }
}
