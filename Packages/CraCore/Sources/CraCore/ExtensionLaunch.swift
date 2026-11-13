import Foundation

/// What a click on an extension's button does (toolbar, sidebar URL pill, Extensions menu,
/// a shortcut): the Mac's MainWindowController performs it, and Windows' BrowserWindow for its
/// Extensions menu (no toolbar there, so never a page to anchor Chrome's popup to). Only an
/// extension installed and turned on in the focused page's profile runs; one turned off in chrome://extensions is out of the toolbar
/// and the menus (GitHub #41) and must not be reached from a stale button or a shortcut either.
public enum ExtensionLaunch: Equatable {
    case nothing
    /// Chrome's action on the focused page; its popup hangs from the toolbar.
    case runAction
    /// No page for Chrome's popup to attach to: the popup page in a popup-sized window.
    case popupWindow(url: String)
    /// No popup at all: the options page, else Chrome's details page for the extension.
    case openTab(url: String)

    public struct Extension: Equatable {
        public let id: String
        public var popupPath: String?
        public var optionsPath: String?
        public var enabled = true

        public init(id: String, popupPath: String? = nil, optionsPath: String? = nil, enabled: Bool = true) {
            self.id = id
            self.popupPath = popupPath
            self.optionsPath = optionsPath
            self.enabled = enabled
        }
    }

    /// `available`: the extensions of the focused page's profile. `hasPage`: a page and a
    /// toolbar to anchor Chrome's popup.
    public static func decide(_ id: String, available: [Extension], hasPage: Bool) -> ExtensionLaunch {
        guard let e = available.first(where: { $0.id == id }), e.enabled else { return .nothing }
        return hasPage ? .runAction : fallback(e)
    }

    /// Also what follows when Chrome could not run the action on the page.
    public static func fallback(_ e: Extension) -> ExtensionLaunch {
        guard e.enabled else { return .nothing }
        let base = "chrome-extension://\(e.id)/"
        if let popup = e.popupPath { return .popupWindow(url: base + popup) }
        return .openTab(url: e.optionsPath.map { base + $0 } ?? "chrome://extensions/?id=\(e.id)")
    }
}
