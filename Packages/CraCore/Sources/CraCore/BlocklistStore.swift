import Foundation
import Observation

/// Settings ▸ Privacy ▸ Block lists (#507): lists added on top of the one Cra ships. Each is
/// fetched (or read, for a file), kept in the data folder's Blocklists folder and fetched again
/// once it's old (CustomBlocklist.isDue). The engine gets Cra's own list and every added list's
/// domains as one set, which the Block ads and trackers switch turns on and off. The Mac and
/// Windows apps each hand it how to fetch a list and how to give the engine its domains.
@MainActor
@Observable
public final class BlocklistStore {
    /// What each app supplies.
    public struct Environment: Sendable {
        /// Where the fetched copies are kept.
        public var folder: URL
        /// Cra's own list (resources/blocklist), as text; read once, off the main thread.
        public var bundled: @Sendable () -> String?
        /// A list's bytes from the web (a file URL is read here).
        public var download: @Sendable (URL) async -> Result<Data, BlockListError>
        /// Hands the engine every domain to block; called off the main thread.
        public var publish: @Sendable ([String]) -> Void
        /// A line for the app's log (never a whole address: `logName`).
        public var log: @Sendable (String) -> Void

        public init(folder: URL, bundled: @escaping @Sendable () -> String?,
                    download: @escaping @Sendable (URL) async -> Result<Data, BlockListError>,
                    publish: @escaping @Sendable ([String]) -> Void, log: @escaping @Sendable (String) -> Void = { _ in }) {
            self.folder = folder
            self.bundled = bundled
            self.download = download
            self.publish = publish
            self.log = log
        }
    }

    /// Fetched copies, by address.
    public private(set) var cached: [String: CachedBlocklist] = [:]
    /// Addresses being fetched now.
    public private(set) var fetching: Set<String> = []
    /// Why the last fetch of an address failed; a good fetch clears it.
    public private(set) var failures: [String: String] = [:]
    /// How many domains the engine was given last, Cra's own among them (0 before the first).
    public private(set) var publishedDomains = 0

    @ObservationIgnored private let env: Environment
    @ObservationIgnored private var addresses: [String] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshTimer: ScheduledWork?
    @ObservationIgnored private var clock: Scheduler?
    /// What the engine was last given: each address with its fetch date.
    @ObservationIgnored private var publishedKey: [String]?
    /// Work still running, so a test (or quitting) can wait for it.
    @ObservationIgnored private var running: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTask = 0
    /// Publishes run one after another, in order.
    @ObservationIgnored private var lastPublish: Task<Void, Never>?
    /// Cra's own list, parsed the first time it's published.
    @ObservationIgnored private let bundled = BundledCache()

    /// A list bigger than this isn't a block list.
    public static let maxBytes = 64 << 20

    public init(environment: Environment) {
        env = environment
    }

    private func cacheURL(_ address: String) -> URL {
        env.folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: address))
    }

    /// `settings.customBlocklists` now. The first call (at launch) reads the kept copies, gives the
    /// engine its set and fetches what's old; later ones forget removed lists and fetch added ones.
    public func set(addresses new: [String], clock: Scheduler) {
        guard started else {
            started = true
            self.clock = clock
            addresses = new
            let files = new.map { ($0, cacheURL($0)) }
            track {
                let kept = await Task.detached(priority: .utility) {
                    files.compactMap { _, file in (try? String(contentsOf: file, encoding: .utf8)).flatMap(CachedBlocklist.init(text:)) }
                }.value
                for list in kept where self.addresses.contains(list.url) { self.cached[list.url] = list }
                self.publish()
                self.refreshDue(atLaunch: true)
            }
            refreshTimer = clock.every(6 * 3600) { [weak self] in self?.refreshDue(atLaunch: false) }
            return
        }
        let (removed, added) = CustomBlocklist.changes(from: addresses, to: new)
        addresses = new
        for address in removed {
            cached[address] = nil
            failures[address] = nil
            let file = cacheURL(address)
            track { await Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }.value }
            env.log("block list \(Self.logName(address)) removed")
        }
        publish()
        added.forEach { fetch($0) }
    }

    /// Fetches the lists that are old, or that have no copy yet.
    private func refreshDue(atLaunch: Bool) {
        guard let clock else { return }
        CustomBlocklist.due(addresses, fetched: cached.mapValues(\.fetched), now: clock.now, atLaunch: atLaunch).forEach { fetch($0) }
    }

    /// Fetches (or reads) one list now. A failure keeps the copy it had.
    public func fetch(_ address: String) {
        guard !fetching.contains(address), let url = URL(string: address) else { return }
        fetching.insert(address)
        let fetchedAt = clock?.now ?? Date()
        let download = env.download
        track {
            let result: Result<CachedBlocklist, BlockListError> = await Task.detached(priority: .utility) {
                let loaded: Result<Data, BlockListError>
                if url.isFileURL {
                    loaded = (try? Data(contentsOf: url)).map { .success($0) } ?? .failure(.unreadable)
                } else {
                    loaded = await download(url)
                }
                return loaded.flatMap(Self.text(from:)).flatMap { text in
                    let list = CachedBlocklist(url: address, list: ParsedBlocklist(text: text), fetched: fetchedAt)
                    return list.domains.isEmpty ? .failure(.noDomains) : .success(list)
                }
            }.value
            self.finish(address, result)
        }
    }

    private func finish(_ address: String, _ result: Result<CachedBlocklist, BlockListError>) {
        fetching.remove(address)
        guard addresses.contains(address) else { return }  // removed while it loaded
        switch result {
        case .success(let list):
            cached[address] = list
            failures[address] = nil
            let text = list.text, file = cacheURL(address), folder = env.folder
            track {
                await Task.detached(priority: .utility) {
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try? text.write(to: file, atomically: true, encoding: .utf8)
                }.value
            }
            publish()
        case .failure(let error):
            failures[address] = error.message
            env.log("block list \(Self.logName(address)) not fetched: \(error.message)")
        }
    }

    /// Gives the engine Cra's list with every added one, when that changed.
    private func publish() {
        let key = CustomBlocklist.engineKey(addresses, fetched: cached.mapValues(\.fetched))
        guard key != publishedKey else { return }
        publishedKey = key
        let lists = addresses.compactMap { cached[$0]?.domains }
        let env = self.env, before = lastPublish, bundled = self.bundled
        let work = Task { @MainActor [weak self] in
            await before?.value
            let count = await Task.detached(priority: .utility) {
                let own = bundled.domains { env.bundled().map { ParsedBlocklist(text: $0).domains } ?? [] }
                let domains = CustomBlocklist.merged([own] + lists)
                env.publish(domains)
                env.log("block lists: \(domains.count) domains, \(lists.count) added \(lists.count == 1 ? "list" : "lists")")
                return domains.count
            }.value
            self?.publishedDomains = count
        }
        lastPublish = work
        track { await work.value }
    }

    /// Waits for every fetch, file write and publish started so far.
    public func settle() async {
        while let task = running.values.first { await task.value }
    }

    private func track(_ body: @escaping @MainActor () async -> Void) {
        nextTask += 1
        let id = nextTask
        running[id] = Task { @MainActor [weak self] in
            await body()
            self?.running[id] = nil
        }
    }

    // MARK: Pure parts

    /// A list's bytes as text: at most `maxBytes`, UTF-8 or else Latin-1.
    nonisolated public static func text(from data: Data) -> Result<String, BlockListError> {
        guard data.count <= maxBytes else { return .failure(.tooBig) }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return .failure(.unreadable) }
        return .success(text)
    }

    /// A list as a log names it: its host, never the whole address.
    nonisolated public static func logName(_ address: String) -> String {
        URL(string: address).flatMap { $0.isFileURL ? "file" : $0.host } ?? "?"
    }
}

/// Cra's own list, read the first time it's needed.
private final class BundledCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String]?

    func domains(_ read: () -> [String]) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if let value { return value }
        let read = read()
        value = read
        return read
    }
}

public enum BlockListError: Error, Equatable, Sendable {
    case network, status(Int), unreadable, tooBig, noDomains

    public var message: String {
        switch self {
        case .network: return "Couldn’t reach the list. Cra tries again later."
        case .status(let code): return "The server answered \(code). Cra tries again later."
        case .unreadable: return "Cra couldn’t read the file."
        case .tooBig: return "The list is bigger than 64 MB."
        case .noDomains: return "Cra found no domain rules it can use in this list."
        }
    }
}
