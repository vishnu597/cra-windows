import Foundation

/// pinned-extensions.json: the extensions pinned to the toolbar, in toolbar order, for each
/// Chromium profile. Arc keeps them per profile: its `arc::BrowserContext` (one per profile)
/// reads and writes Chromium's `extensions.pinned_extensions` pref, so a space shows the pins of
/// the profile it is bound to (GitHub #107). Cra kept one list for every profile before that, a
/// plain array. That list still serves each profile that has not pinned or unpinned anything
/// itself, so an update changes no toolbar, and a file with no list of a profile's own is still
/// written as that array.
public struct PinnedExtensions: Codable, Equatable, Sendable {
    /// The pins of every profile without a list of its own.
    public var shared: [String]
    /// Lists of profiles whose pins changed, by profile folder ("Default", "Profile <id>").
    public var profiles: [String: [String]]

    public init(shared: [String] = [], profiles: [String: [String]] = [:]) {
        self.shared = shared
        self.profiles = profiles
    }

    /// Chromium extension IDs in toolbar order.
    public func ids(inProfile profile: String) -> [String] { profiles[profile] ?? shared }

    public func isPinned(_ id: String, inProfile profile: String) -> Bool { ids(inProfile: profile).contains(id) }

    /// The toolbar's pins (Windows' ToolbarView): the profile's pinned extensions that are
    /// installed and turned on, in toolbar order, each once. A pin of an extension that is
    /// turned off, or gone, shows no button: running one crashes Chromium (the Mac's #41).
    public func toolbarIDs(inProfile profile: String, enabled: Set<String>) -> [String] {
        var seen = Set<String>()
        return ids(inProfile: profile).filter { enabled.contains($0) && seen.insert($0).inserted }
    }

    /// The extensions menu's order (Arc): the pinned ones in toolbar order, then the rest by name.
    /// Each ID once: two installs of one extension (two folders with the same manifest key) or a
    /// pin saved twice listed it twice, and the menu's icon map trapped on the repeat (0.1.43).
    public func menuOrder<E>(_ entries: [E], inProfile profile: String, id: (E) -> String, name: (E) -> String) -> [E] {
        var seen = Set<String>()
        let pinned = ids(inProfile: profile).compactMap { pin in seen.insert(pin).inserted ? entries.first { id($0) == pin } : nil }
        let rest = entries.filter { !isPinned(id($0), inProfile: profile) && seen.insert(id($0)).inserted }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        return pinned + rest
    }

    /// Pins or unpins in one profile only; the others keep what they show.
    public mutating func setPinned(_ id: String, _ pinned: Bool, inProfile profile: String) {
        guard pinned != isPinned(id, inProfile: profile) else { return }
        var list = ids(inProfile: profile)
        if pinned { list.append(id) } else { list.removeAll { $0 == id } }
        profiles[profile] = list
    }

    public mutating func move(_ id: String, to index: Int, inProfile profile: String) {
        var list = ids(inProfile: profile)
        guard let from = list.firstIndex(of: id) else { return }
        list.remove(at: from)
        list.insert(id, at: min(max(0, index), list.count))
        profiles[profile] = list
    }

    /// A new profile's pins from the browser it was imported from (GitHub #131); a profile that
    /// already has a list of its own keeps it.
    public mutating func seed(_ ids: [String], inProfile profile: String) {
        guard profiles[profile] == nil, ids != shared else { return }
        profiles[profile] = ids
    }

    /// Chromium's pinned extensions in a profile's Preferences file (`extensions.pinned_extensions`),
    /// in toolbar order; nil when the file has none.
    public static func chromiumPins(preferences data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["extensions"] as? [String: Any])?["pinned_extensions"] as? [String]
    }

    /// An import's pins (GitHub #131, the Mac's ImportFlow.seedPinnedExtensions): each Cra profile
    /// the import used shows the pins its source profile had, `sources` by source profile folder.
    /// An import that bound no profiles brings the source's Default to Cra's Default. Default's
    /// become everyone's list only while Cra has none (`hasSavedPins`: pinned-extensions.json
    /// exists); another profile keeps a list of its own it already has.
    public mutating func seedImport(_ sources: [String: [String]], map: ImportProfileMap, hasSavedPins: Bool) {
        let pairs = map.bindsProfiles ? map.folders : ["Default": "Default"]
        for (source, target) in pairs.sorted(by: { ($0.value == "Default" ? 0 : 1, $0.key) < ($1.value == "Default" ? 0 : 1, $1.key) }) {
            guard let ids = sources[source] else { continue }
            if target == "Default" {
                guard !hasSavedPins, shared.isEmpty, profiles["Default"] == nil else { continue }
                shared = ids
            } else {
                seed(ids, inProfile: target)
            }
        }
    }

    /// Drops the extensions `isGone` says are no longer installed, from every list.
    public mutating func removeAll(where isGone: (String) -> Bool) {
        shared.removeAll(where: isGone)
        for key in profiles.keys { profiles[key]?.removeAll(where: isGone) }
    }

    private enum CodingKeys: String, CodingKey { case shared, profiles }

    public init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([String].self) {
            self.init(shared: list)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(shared: try c.decodeIfPresent([String].self, forKey: .shared) ?? [],
                  profiles: try c.decodeIfPresent([String: [String]].self, forKey: .profiles) ?? [:])
    }

    public func encode(to encoder: Encoder) throws {
        if profiles.isEmpty {
            var c = encoder.singleValueContainer()
            try c.encode(shared)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shared, forKey: .shared)
        try c.encode(profiles, forKey: .profiles)
    }
}
