import Foundation

/// Native messaging hosts on Windows (the Mac's NativeMessagingHosts): extensions that talk to a
/// desktop app (1Password, Bitwarden, Claude…) find it through a host manifest that the app
/// registers for the browsers it knows, under `Software\Google\Chrome\NativeMessagingHosts\<name>`
/// and the like, never for Cra. Cra's Chromium reads `Software\Chromium\NativeMessagingHosts`,
/// so at each launch Cra copies the other browsers' entries there, as the Mac links their
/// manifests into its own folder. It keeps a list of the entries it made, so an app that is
/// uninstalled goes again and entries someone else made stay.
public enum NativeMessagingMirror {
    /// Hosts that let a desktop app drive "Chrome" through its extension (the Mac's excluded):
    /// ChatGPT's computer use would take over Cra's window instead of using the user's Chrome.
    public static let excluded: Set<String> = ["com.openai.codexextension"]

    /// What the launch changes in Cra's key.
    public struct Plan: Equatable, Sendable {
        /// Host name to manifest path, to write.
        public var write: [String: String] = [:]
        /// Host names to delete: Cra's own entries whose app has gone.
        public var remove: [String] = []
        /// The entries Cra owns afterwards, saved for the next launch.
        public var owned: Set<String> = []

        public init(write: [String: String] = [:], remove: [String] = [], owned: Set<String> = []) {
            self.write = write
            self.remove = remove
            self.owned = owned
        }
    }

    /// `sources`: each browser's hosts (name to manifest path), Chrome first; the first browser
    /// with a name wins, as on the Mac. `present`: Cra's key as it is. `owned`: the entries Cra
    /// made at the last launch. `manifestExists`: an entry whose manifest file is gone is skipped.
    public static func plan(sources: [[String: String]], present: [String: String], owned: Set<String>,
                            manifestExists: (String) -> Bool) -> Plan {
        var wanted: [String: String] = [:]
        for hosts in sources {
            for (name, path) in hosts where wanted[name] == nil && !excluded.contains(name.lowercased()) && manifestExists(path) {
                wanted[name] = path
            }
        }
        var plan = Plan()
        for name in owned.sorted() where wanted[name] == nil && present[name] != nil { plan.remove.append(name) }
        for (name, path) in wanted {
            // Someone else's entry (their own Chromium's) stays as it is.
            if present[name] != nil, !owned.contains(name) { continue }
            plan.owned.insert(name)
            if present[name] != path { plan.write[name] = path }
        }
        return plan
    }
}
