import Foundation
import WinSDK

/// Cra as the default browser (SystemIntegration.makeDefaultBrowser on the Mac). Windows lets
/// only the user pick it, in Settings ▸ Apps ▸ Default apps, among the browsers registered under
/// HKEY_CURRENT_USER, as Chrome and Edge register a per-user install: Cra registers when the
/// user asks to make it the default, then opens its page there. A link then starts
/// `Cra.exe --single-argument <url>`; Chromium hands a second launch to the Cra that runs.
enum DefaultBrowser {
    /// The ProgID http, https and the HTML files open with.
    static let progID = "CraHTML"
    static let name = "Cra"
    private static let client = #"Software\Clients\StartMenuInternet\Cra"#
    private static let classes = #"Software\Classes\CraHTML"#
    private static let capabilities = client + #"\Capabilities"#
    private static let registered = #"Software\RegisteredApplications"#
    private static let fileTypes = [".htm", ".html", ".shtml", ".xht", ".xhtml", ".svg", ".pdf"]

    /// Windows opens https links with Cra (the user's choice in Settings).
    static var isDefault: Bool { currentProgID == progID }

    /// The browser https links open with now, by name, when it isn't Cra and Windows names it.
    static var currentName: String? {
        guard let id = currentProgID, id != progID,
              let name = WinRegistry.string(id + #"\Application"#, "ApplicationName", root: WinRegistry.classesRoot),
              !name.isEmpty, !name.hasPrefix("@") else { return nil }
        return name
    }

    private static var currentProgID: String? {
        WinRegistry.string(#"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice"#, "ProgId")
    }

    /// Registers Cra and opens its page in Settings ▸ Default apps, where the user makes it
    /// the default. False when the registry refused.
    @discardableResult
    static func makeDefault() -> Bool {
        guard register() else { return false }
        Shell.open("ms-settings:defaultapps?registeredAppUser=\(name)")
        return true
    }

    /// Points a registration made by an earlier copy at this Cra.exe (the build moved).
    static func updateRegistrationIfMoved() {
        guard let exe = LaunchAtLogin.executablePath, let command = WinRegistry.string(classes + #"\shell\open\command"#, ""),
              command != openCommand(exe) else { return }
        register()
    }

    @discardableResult
    private static func register() -> Bool {
        guard let exe = LaunchAtLogin.executablePath else { return false }
        let icon = "\"\(exe)\",0"
        let values: [(String, String, String)] = [
            (classes, "", "Cra HTML Document"),
            (classes, "URL Protocol", ""),
            (classes + #"\Application"#, "ApplicationName", name),
            (classes + #"\Application"#, "ApplicationIcon", icon),
            (classes + #"\DefaultIcon"#, "", icon),
            (classes + #"\shell\open\command"#, "", openCommand(exe)),
            (client, "", name),
            (client + #"\DefaultIcon"#, "", icon),
            (client + #"\shell\open\command"#, "", "\"\(exe)\""),
            (capabilities, "ApplicationName", name),
            (capabilities, "ApplicationDescription", "Cra, the browser with Arc's sidebar and spaces."),
            (capabilities, "ApplicationIcon", icon),
            (capabilities + #"\StartMenu"#, "StartMenuInternet", name),
            (capabilities + #"\URLAssociations"#, "http", progID),
            (capabilities + #"\URLAssociations"#, "https", progID),
            (registered, name, capabilities),
        ] + fileTypes.map { (capabilities + #"\FileAssociations"#, $0, progID) }
        guard values.allSatisfy({ WinRegistry.setString($0.0, $0.1, $0.2) }) else { return false }
        // SHCNE_ASSOCCHANGED, SHCNF_IDLIST: Explorer and Settings read the new registration.
        SHChangeNotify(0x0800_0000, 0, nil, nil)
        return true
    }

    /// Chrome's form: everything after the switch is the link, spaces and quotes included, so
    /// a link can't add switches of its own.
    private static func openCommand(_ exe: String) -> String { "\"\(exe)\" --single-argument %1" }
}
