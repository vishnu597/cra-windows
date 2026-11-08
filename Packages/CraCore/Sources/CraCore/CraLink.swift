import Foundation

/// What a cra:// link asks Cra to do (AppDelegate.handleInternalURL on the Mac, which Windows'
/// WindowList.openCraLink follows): cra://commandbar?query=…&mode=edit, cra://dismiss,
/// cra://open?url=…[&space=<space id>][&background=1|&little=1], cra://action/<id>,
/// cra://navigate?url=…. Which apps may send which ones is `ExternalLink.isUserFacing`.
public enum CraLink: Equatable, Sendable {
    /// The command bar: Ctrl+L's (`editURL`) with mode=edit, else New Tab's; `query` typed into it.
    case commandBar(query: String?, editURL: Bool)
    /// Closes whatever transient UI is up (the command bar, the find bar, a popover).
    case dismiss
    /// A tab on `url`: in `space` when it names one, in the background (unread) with
    /// background=1, or in a Little Window with little=1.
    case open(url: String, space: UUID?, background: Bool, little: Bool)
    /// A command by its id (`KeyBindingDefaults`), as its shortcut runs it.
    case action(String)
    /// `url` in the selected tab.
    case navigate(String)
    /// A cra:// link Cra knows but this app doesn't do (key, import, debug on Windows), or one
    /// it doesn't know; its host.
    case other(String)

    /// Nil for anything that isn't a cra:// link, and for open and navigate without a url.
    public init?(_ link: String) {
        guard let u = URL(string: link), u.scheme?.lowercased() == "cra" else { return nil }
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let host = u.host?.lowercased() ?? ""
        switch host {
        case "commandbar":
            self = .commandBar(query: q("query"), editURL: q("mode") == "edit")
        case "dismiss":
            self = .dismiss
        case "open":
            guard let url = q("url"), !url.isEmpty else { return nil }
            self = .open(url: url, space: q("space").flatMap(UUID.init(uuidString:)), background: q("background") == "1",
                         little: q("little") == "1")
        case "action":
            let id = String(u.path.drop { $0 == "/" })
            self = id.isEmpty ? .other(host) : .action(id)
        case "navigate":
            guard let url = q("url"), !url.isEmpty else { return nil }
            self = .navigate(url)
        default:
            self = .other(host)
        }
    }
}
