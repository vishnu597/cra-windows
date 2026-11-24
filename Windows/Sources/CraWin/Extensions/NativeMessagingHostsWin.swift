import CraCore
import Foundation
import WinSDK

/// Extensions that talk to a desktop app (1Password, Bitwarden, Claude…) find it through a native
/// messaging host the app registers for Chrome, Edge or Brave, never for Cra. Before Chromium
/// starts, Cra copies those entries into the key its Chromium reads (CraCore's
/// NativeMessagingMirror, the Mac's NativeMessagingHosts), keeping a list of the ones it made in
/// native-messaging-hosts.json so they go once their app does.
enum NativeMessagingHostsWin {
    /// Where Cra's Chromium (Chromium-branded CEF) looks, under HKEY_CURRENT_USER.
    static let target = #"Software\Chromium\NativeMessagingHosts"#

    /// The browsers apps register for, Chrome first; each per user, then for all users (and the
    /// 32-bit view an older installer writes).
    private static let browsers = [#"Google\Chrome"#, #"Microsoft\Edge"#, #"BraveSoftware\Brave-Browser"#]

    private static var ownedFile: URL { WinPaths.supportDir.appendingPathComponent("native-messaging-hosts.json") }

    static func mirror() {
        var sources: [[String: String]] = []
        for browser in browsers {
            sources.append(hosts(#"Software\"# + browser + #"\NativeMessagingHosts"#, root: nil))
            sources.append(hosts(#"SOFTWARE\"# + browser + #"\NativeMessagingHosts"#, root: WinRegistry.localMachine))
            sources.append(hosts(#"SOFTWARE\WOW6432Node\"# + browser + #"\NativeMessagingHosts"#, root: WinRegistry.localMachine))
        }
        let owned = (try? Data(contentsOf: ownedFile)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let plan = NativeMessagingMirror.plan(sources: sources, present: hosts(target, root: nil), owned: Set(owned),
                                              manifestExists: { FileManager.default.fileExists(atPath: $0) })
        for name in plan.remove where !WinRegistry.deleteKey(target + #"\"# + name) {
            print("Cra: native messaging host \(name) could not be removed")
        }
        for (name, path) in plan.write where !WinRegistry.setString(target + #"\"# + name, "", path) {
            print("Cra: native messaging host \(name) could not be registered")
        }
        if !plan.write.isEmpty || !plan.remove.isEmpty {
            print("Cra: native messaging hosts: \(plan.write.count) registered, \(plan.remove.count) removed, \(plan.owned.count) in all")
        }
        if plan.owned != Set(owned) {
            try? JSONEncoder().encode(plan.owned.sorted()).write(to: ownedFile, options: .atomic)
        }
    }

    /// The hosts under `key`: each subkey's name and its default value, the manifest's path.
    private static func hosts(_ key: String, root: HKEY?) -> [String: String] {
        var hosts: [String: String] = [:]
        for name in WinRegistry.subkeys(key, root: root) {
            if let path = WinRegistry.string(key + #"\"# + name, "", root: root), !path.isEmpty { hosts[name] = path }
        }
        return hosts
    }
}
