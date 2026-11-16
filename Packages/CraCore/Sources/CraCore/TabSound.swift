import Foundation

/// Arc 1.171's speaker on a tab's row, between the favicon and the title: a playing or muted tab
/// shows it (not while its name is being edited), and a click mutes or unmutes the tab
/// (31 Oct 2026, issue #28). Both apps draw it from this.
public enum TabSound: Equatable, Sendable {
    case playing
    case muted

    /// The speaker a row shows, or nil for none.
    public static func button(muted: Bool, audible: Bool, editing: Bool = false) -> TabSound? {
        guard !editing else { return nil }
        if muted { return .muted }
        return audible ? .playing : nil
    }

    /// The SF Symbol the Mac draws (the Windows app maps it to Segoe Fluent Icons).
    public var symbol: String { self == .muted ? "speaker.slash" : "speaker.wave.3" }

    /// The button's tooltip: what a click does.
    public var help: String { self == .muted ? "Unmute Tab" : "Mute Tab" }

    /// The tab menu's item for a tab that is or isn't muted.
    public static func menuTitle(muted: Bool) -> String { muted ? "Unmute" : "Mute" }
}
