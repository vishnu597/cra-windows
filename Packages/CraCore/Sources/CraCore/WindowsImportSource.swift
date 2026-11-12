import Foundation

/// A browser Cra on Windows can import from, and where it keeps its data: the Mac's list
/// (`ImportSource` in the app) with Windows' folders. Chromium browsers keep "User Data" under
/// %LOCALAPPDATA% (Opera under %APPDATA%); Arc, a packaged app, keeps its files under
/// %LOCALAPPDATA%\Packages\TheBrowserCompany.Arc_<publisher>\LocalCache\Local\Arc. Dia and Safari
/// don't run on Windows; Firefox and Zen come with their SQLite reader.
public struct WindowsImportSource: Identifiable, Hashable {
    public enum Kind: Hashable {
        /// Arc's own sidebar files (StorableSidebar.json and friends).
        case arc
        /// Bookmarks and the last session of each Chromium profile.
        case chromium
    }

    /// The Windows folder a source's path starts from.
    public enum Root: Hashable {
        /// %LOCALAPPDATA%.
        case local
        /// %APPDATA%.
        case roaming
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let root: Root
    /// Folders under `root`: Chromium's "User Data" (Opera's profile folder), or Arc's support folder.
    public let path: [String]

    public init(id: String, name: String, kind: Kind, root: Root, path: [String]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.root = root
        self.path = path
    }

    /// Where Windows keeps per-user app data.
    public struct Folders: Equatable {
        public var local: URL
        public var roaming: URL

        public init(local: URL, roaming: URL) {
            self.local = local
            self.roaming = roaming
        }

        /// From %LOCALAPPDATA% and %APPDATA%; nil when either is missing.
        public init?(environment: [String: String]) {
            guard let local = environment["LOCALAPPDATA"], !local.isEmpty,
                  let roaming = environment["APPDATA"], !roaming.isEmpty else { return nil }
            self.init(local: URL(fileURLWithPath: local, isDirectory: true), roaming: URL(fileURLWithPath: roaming, isDirectory: true))
        }
    }

    static func chromium(_ id: String, _ name: String, _ root: Root = .local, _ path: String...) -> WindowsImportSource {
        WindowsImportSource(id: id, name: name, kind: .chromium, root: root, path: path)
    }

    /// Arc's package folder, whatever its publisher suffix.
    public static let arcPackagePrefix = "TheBrowserCompany.Arc_"

    public static let arc = WindowsImportSource(id: "arc", name: "Arc", kind: .arc, root: .local, path: ["Packages", arcPackagePrefix, "LocalCache", "Local", "Arc"])

    /// In the Mac's order (Dia's list), without the browsers Windows doesn't have.
    public static let all: [WindowsImportSource] = [
        arc,
        chromium("chrome", "Chrome", .local, "Google", "Chrome", "User Data"),
        chromium("brave", "Brave", .local, "BraveSoftware", "Brave-Browser", "User Data"),
        chromium("edge", "Edge", .local, "Microsoft", "Edge", "User Data"),
        chromium("opera", "Opera", .roaming, "Opera Software", "Opera Stable"),
        chromium("operagx", "Opera GX", .roaming, "Opera Software", "Opera GX Stable"),
        chromium("vivaldi", "Vivaldi", .local, "Vivaldi", "User Data"),
        chromium("chromium", "Chromium", .local, "Chromium", "User Data"),
    ]

    /// The source's folder: Chromium's User Data, or Arc's support folder (nil when Arc's package
    /// isn't there).
    public func folder(in folders: Folders) -> URL? {
        var url = root == .local ? folders.local : folders.roaming
        for component in path {
            if kind == .arc && component == Self.arcPackagePrefix {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                guard let package = names.filter({ $0.hasPrefix(Self.arcPackagePrefix) }).sorted().first else { return nil }
                url = url.appendingPathComponent(package, isDirectory: true)
            } else {
                url = url.appendingPathComponent(component, isDirectory: true)
            }
        }
        return url
    }

    /// Chromium's User Data folder, with Local State (the key passwords and cookies are sealed
    /// with) beside the profiles: Arc's is inside its support folder.
    public func userData(in folders: Folders) -> URL? {
        folder(in: folders).map { kind == .arc ? ArcImporter.userData(in: $0) : $0 }
    }

    /// The Chromium profiles whose data can come over (Arc's own, for Arc).
    public func profiles(in folders: Folders) -> [ChromiumProfile] {
        guard let dir = folder(in: folders) else { return [] }
        return ChromiumImporter.profiles(userData: kind == .arc ? ArcImporter.userData(in: dir) : dir)
    }

    /// Has data to bring over.
    public func isAvailable(in folders: Folders) -> Bool {
        guard let dir = folder(in: folders) else { return false }
        switch kind {
        case .arc: return ArcImporter.isAvailable(in: dir)
        case .chromium: return !ChromiumImporter.profiles(userData: dir).isEmpty
        }
    }

    public static func available(in folders: Folders) -> [WindowsImportSource] {
        all.filter { $0.isAvailable(in: folders) }
    }

    /// What importing this browser adds. Arc on Windows keeps no preferences Cra reads.
    public func plan(in folders: Folders) throws -> ImportPlan {
        guard let dir = folder(in: folders) else { throw ImportError.notFound(name) }
        switch kind {
        case .arc: return try ArcImporter.plan(supportDir: dir, preferences: .init())
        case .chromium: return try ChromiumImporter.plan(browser: name, userData: dir)
        }
    }
}
