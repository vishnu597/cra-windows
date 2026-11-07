import Foundation

/// A link another app hands Cra: the Mac's open-URL events, or a Windows launch with a URL or
/// an HTML file on its command line (Cra as the default browser). Which ones Cra opens, and
/// where (Arc's Air Traffic Control, `LinkRouting`).
public enum ExternalLink {
    public enum Target: Equatable, Sendable {
        /// One of Cra's own cra:// links that another app may open (`isUserFacing`).
        case internalURL
        /// A cra:// link that drives Cra (scripting), which other apps may not use unless the
        /// user allowed it.
        case ignored
        case littleWindow
        /// A new foreground tab in this space's Today list.
        case space(UUID)
        /// A new foreground tab in the space of the normal window used last.
        case mostRecentSpace
    }

    /// The first matching route, else the default (Settings ▸ Tabs ▸ "Links from other apps
    /// open in a Little Window"); a route to a space that is gone opens in the most recent one.
    public static func target(for url: String, settings: AppSettings, allowsScripting: Bool = false,
                              spaceExists: (UUID) -> Bool) -> Target {
        if let u = URL(string: url), u.scheme?.lowercased() == "cra" {
            return isUserFacing(u) || allowsScripting ? .internalURL : .ignored
        }
        switch settings.destination(forExternalURL: url) {
        case .littleWindow: return .littleWindow
        case .space(let id) where spaceExists(id): return .space(id)
        case .space, .mostRecentSpace: return .mostRecentSpace
        }
    }

    /// The cra:// links any app may open: they do what the user could do from the Dock (the
    /// command bar, dismissing it, opening a web page). The rest (action, navigate, key, import,
    /// debug, open with a file: or javascript: URL) run scripts, DevTools Protocol and key
    /// presses, so a link in a mail or another browser must not reach them.
    public static func isUserFacing(_ u: URL) -> Bool {
        switch u.host {
        case "commandbar", "dismiss":
            return true
        case "open":
            let target = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            let scheme = target.flatMap { URL(string: $0)?.scheme?.lowercased() }
            return scheme == "http" || scheme == "https"
        default:
            return false
        }
    }

    /// The links on a launch's command line, in order: web, file and cra:// links as they are,
    /// Windows paths (an .html file opened from Explorer) as file:// URLs. Chromium's switches,
    /// the `--` before the link and anything else are left out.
    public static func links(inArguments arguments: [String]) -> [String] {
        arguments.compactMap(link)
    }

    private static let schemes = ["http://", "https://", "file://", "cra://"]

    private static func link(_ argument: String) -> String? {
        let s = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("-") else { return nil }
        let lower = s.lowercased()
        if schemes.contains(where: lower.hasPrefix) { return s }
        return fileURL(windowsPath: s)
    }

    /// `C:\Users\me\a b.html` → `file:///C:/Users/me/a%20b.html`, `\\server\share\x.html` →
    /// `file://server/share/x.html`; nil for anything that isn't an absolute Windows path.
    public static func fileURL(windowsPath path: String) -> String? {
        let chars = Array(path)
        let drive = chars.count >= 3 && chars[0].isASCII && chars[0].isLetter && chars[1] == ":" && (chars[2] == "\\" || chars[2] == "/")
        let unc = path.hasPrefix("\\\\") && path.count > 2
        guard drive || unc else { return nil }
        let parts = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true)
        // ASCII letters, digits and the path's own punctuation; "?", "#", spaces and anything
        // else in a file name is escaped (UTF-8).
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@")
        let encoded = parts.map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
        guard let first = encoded.first else { return nil }
        return drive ? "file:///" + encoded.joined(separator: "/")
            : "file://" + first + (encoded.count > 1 ? "/" + encoded.dropFirst().joined(separator: "/") : "")
    }
}
