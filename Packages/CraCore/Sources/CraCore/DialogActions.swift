import Foundation

public struct DialogAction: Equatable, Sendable {
    public enum Role: Sendable { case primary, secondary, destructive, cancel }

    public let title: String
    public let role: Role

    public init(_ title: String, role: Role = .primary) {
        self.title = title
        self.role = role
    }

    public static let cancel = DialogAction("Cancel", role: .cancel)
}

public struct DialogActions: Equatable, Sendable {
    public let buttons: [DialogAction]

    public init(_ buttons: [DialogAction]) {
        precondition(!buttons.isEmpty, "A dialog needs at least one button")
        self.buttons = buttons
    }

    public var defaultIndex: Int? {
        buttons.firstIndex { $0.role == .primary || $0.role == .destructive }
    }

    public var cancelIndex: Int? {
        buttons.firstIndex { $0.role == .cancel } ?? (buttons.count == 1 ? 0 : nil)
    }

    public var displayOrder: [Int] {
        let others = buttons.indices.reversed().filter { $0 != defaultIndex }
        return others + (defaultIndex.map { [$0] } ?? [])
    }

    /// Buttons at the card's left edge: secondary choices such as Arc's "Quit, and don’t ask again".
    public var leadingOrder: [Int] { displayOrder.filter { buttons[$0].role == .secondary } }

    /// Buttons at the card's right edge, the default last.
    public var trailingOrder: [Int] { displayOrder.filter { buttons[$0].role != .secondary } }

    public func key(at index: Int) -> String {
        if index == defaultIndex { return "↩" }
        return index == cancelIndex ? "ESC" : ""
    }

    public func isEnabled(at index: Int, input: String?, requiresInput: Bool) -> Bool {
        index != defaultIndex || !requiresInput || !(input ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The colours of Arc's dialog-sheet buttons (the Mac's DialogButton, captured from Arc 1.172.1's
/// Quit and Delete Space sheets), as hex for an app without SwiftUI to draw: Windows' card.
public struct DialogButtonColors: Equatable, Sendable {
    public enum Style: Equatable, Sendable { case secondary, primary, accent, destructive }

    public let fill: String
    /// The 1 pt rim, nil for none.
    public let rim: String?
    public let title: String
    public let badgeFill: String
    public let badgeRim: String?
    public let badgeText: String
    /// The darker lip 1.5 pt under a default button, nil for none.
    public let lip: String?
    /// Under the pointer: white for the plain buttons, black for the coloured ones, at 10 %.
    public let hoverIsWhite: Bool

    /// The style a button of `role` takes: the default one is Arc's blue, Delete red.
    public static func style(for role: DialogAction.Role) -> Style {
        switch role {
        case .primary: .accent
        case .destructive: .destructive
        case .secondary, .cancel: .secondary
        }
    }

    public init(_ style: Style, enabled: Bool = true) {
        let accent = style == .accent && enabled, destructive = style == .destructive && enabled
        let primary = style != .secondary
        fill = destructive ? "#F53516" : accent ? "#3239FB" : primary ? (enabled ? "#3B3C8F" : "#1C1D4C") : "#302F60"
        rim = destructive ? "#F53516" : accent ? "#5B61FD" : primary ? (enabled ? "#6362A9" : nil) : "#6362A9"
        title = accent || destructive ? "#FFFFFF" : enabled ? "#EBEBEF" : "#5B5C7F"
        badgeFill = destructive ? "#F74C31" : accent ? "#464DFB" : primary ? (enabled ? "#4E4C9A" : "#222469") : "#4E4C77"
        badgeRim = destructive ? "#FA624C" : accent ? "#6B71FE" : nil
        badgeText = destructive ? "#FFFFFF" : accent ? "#EDEDFF" : enabled ? "#B7B7DD" : "#5F6193"
        lip = style == .accent ? (enabled ? "#2C3475" : "#1D2259") : destructive ? "#41232A" : nil
        hoverIsWhite = style == .secondary
    }

    /// The card under the buttons and its body text.
    public static let card = "#161C2F"
    public static let body = "#B8B9C4"
}
