import Foundation

/// File ▸ Save Page As (Arc's ⇧⌘S): the page in one file, the way Chrome's "Web Page, Single
/// File" (MHTML from DevTools' `Page.captureSnapshot`) or "Web Page, HTML Only" (the document's
/// markup as it stands) saves it. The Mac's PageCommands.savePageAs asks DevTools the same; the
/// Windows app takes the whole decision from here.
public enum SavePage {
    public enum Format: Int, CaseIterable, Equatable, Sendable {
        case singleFile
        case htmlOnly

        /// The Save dialog's file type, as the Mac's Format pop-up names it.
        public var typeName: String {
            switch self {
            case .singleFile: return "Web Page, Single File"
            case .htmlOnly: return "Web Page, HTML Only"
            }
        }

        public var fileExtension: String {
            switch self {
            case .singleFile: return "mhtml"
            case .htmlOnly: return "html"
            }
        }

        /// The DevTools method and its parameters that return the file's text.
        public var request: (method: String, params: String) {
            switch self {
            case .singleFile: return ("Page.captureSnapshot", #"{"format":"mhtml"}"#)
            case .htmlOnly:
                return ("Runtime.evaluate",
                        #"{"expression":"'<!DOCTYPE html>\n'+document.documentElement.outerHTML","returnByValue":true}"#)
            }
        }

        /// The file's text from DevTools' answer to `request`; nil when it has none.
        public func contents(fromReply json: String?) -> String? {
            guard let json, let reply = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
            switch self {
            case .singleFile: return reply["data"] as? String
            case .htmlOnly: return (reply["result"] as? [String: Any])?["value"] as? String
            }
        }
    }

    /// The name the dialog suggests: the page's title, "Page" without one, with the characters
    /// a file name can't hold (on Windows or the Mac) turned into hyphens, and the format's
    /// extension. The Mac replaces only `/` and `:`, which are all macOS refuses.
    public static func suggestedFileName(title: String, format: Format = .singleFile) -> String {
        let forbidden: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        var base = String(title.map { forbidden.contains($0) || $0.isNewline || $0 == "\t" ? "-" : $0 })
        base = base.trimmingCharacters(in: .whitespaces)
        // Windows drops trailing dots and spaces, and a long title makes a path Explorer can't open.
        while base.hasSuffix(".") || base.hasSuffix(" ") { base.removeLast() }
        if base.count > 120 { base = String(base.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return (base.isEmpty ? "Page" : base) + "." + format.fileExtension
    }

    /// The format a chosen path saves in: its extension decides (someone who types `.html`
    /// gets HTML whatever type the dialog shows), else the dialog's type.
    public static func format(forPath path: String, chosenType: Format) -> Format {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return .htmlOnly
        case "mhtml", "mht": return .singleFile
        default: return chosenType
        }
    }
}

/// Edit ▸ Find ▸ Use Selection to Find (⌘E on the Mac): the page's selection, read through
/// DevTools, becomes the find bar's search (MainWindowController.useSelectionForFind).
public enum FindSelection {
    /// `Runtime.evaluate`'s parameters that return the selection as text.
    public static let evaluateParams = #"{"expression":"getSelection().toString()","returnByValue":true}"#

    /// The search from DevTools' answer: the selection without the whitespace around it; nil
    /// when nothing (or only whitespace) is selected, which leaves the bar as it was.
    public static func query(fromReply json: String?) -> String? {
        guard let json, let reply = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let value = (reply["result"] as? [String: Any])?["value"] as? String else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Whether the window must search itself after putting `selection` in the bar: a field that
    /// already holds it doesn't change, so its typing search never runs.
    public static func needsSearch(selection: String, barQuery: String) -> Bool { selection == barQuery }

    /// Edit ▸ Find ▸ Jump to Selection (⌘J on the Mac): the page scrolls its selection into view
    /// (PageCommands.jumpToSelection).
    public static let jumpScript = "(()=>{const s=getSelection();if(!s.rangeCount)return;const n=s.getRangeAt(0).startContainer;"
        + "(n.nodeType===1?n:n.parentElement)?.scrollIntoView({block:'center'});})()"
}
