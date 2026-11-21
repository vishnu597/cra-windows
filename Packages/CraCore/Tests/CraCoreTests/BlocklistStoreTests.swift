import CraCore
import Foundation
import Testing

/// Settings ▸ Privacy ▸ Block lists (#507) as both apps run it (BlocklistStore): kept copies,
/// fetching what's due, failures, removal, and what the engine is handed.
@MainActor
struct BlocklistStoreTests {
    /// What the fake web and engine saw, from any thread.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var _published: [[String]] = []
        private var _downloads: [String] = []
        var pages: [String: Result<Data, BlockListError>] = [:]

        var published: [[String]] { lock.lock(); defer { lock.unlock() }; return _published }
        var downloads: [String] { lock.lock(); defer { lock.unlock() }; return _downloads }
        func publish(_ domains: [String]) { lock.lock(); _published.append(domains); lock.unlock() }
        func download(_ url: URL) -> Result<Data, BlockListError> {
            lock.lock()
            defer { lock.unlock() }
            _downloads.append(url.absoluteString)
            return pages[url.absoluteString] ?? .failure(.network)
        }
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-blocklists-\(UUID().uuidString)", isDirectory: true)
    let log = Log()
    let a = "https://lists.example/a.txt"
    let b = "https://lists.example/b.txt"

    func store() -> BlocklistStore {
        let log = self.log
        return BlocklistStore(environment: .init(folder: folder, bundled: { "own.example\n0.0.0.0 ads.example\n" },
                                                 download: { log.download($0) }, publish: { log.publish($0) }))
    }

    func keep(_ address: String, domains: [String], fetched: Date) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let list = CachedBlocklist(url: address, list: ParsedBlocklist(text: domains.joined(separator: "\n")), fetched: fetched)
        try list.text.write(to: folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: address)), atomically: true, encoding: .utf8)
    }

    @Test func launchReadsKeptCopiesAndFetchesWhatsMissing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualScheduler()
        try keep(a, domains: ["kept.example"], fetched: clock.now.addingTimeInterval(-3600))
        log.pages[b] = .success(Data("! Title: Bee list\n||bee.example^\n||bee.example^$domain=x.example\n".utf8))
        let lists = store()
        lists.set(addresses: [a, b], clock: clock)
        await lists.settle()

        #expect(log.downloads == [b], "a copy an hour old isn't due at launch; one with no copy is")
        #expect(lists.cached[a]?.domains == ["kept.example"] && lists.cached[b]?.name == "Bee list")
        #expect(lists.cached[b]?.skippedRules == 1 && lists.failures.isEmpty && lists.fetching.isEmpty)
        #expect(log.published.last == ["own.example", "ads.example", "kept.example", "bee.example"], "Cra's own list first, each domain once")
        #expect(lists.publishedDomains == 4)
        let saved = try String(contentsOf: folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: b)), encoding: .utf8)
        #expect(CachedBlocklist(text: saved)?.domains == ["bee.example"], "the fetched copy is kept for the next launch")
    }

    @Test func aFailedFetchSaysWhyAndKeepsTheEngineAsItWas() async {
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualScheduler()
        log.pages[a] = .failure(.status(404))
        log.pages[b] = .success(Data("# nothing but a comment\n".utf8))
        let lists = store()
        lists.set(addresses: [a, b], clock: clock)
        await lists.settle()
        #expect(lists.failures[a] == BlockListError.status(404).message)
        #expect(lists.failures[b] == BlockListError.noDomains.message)
        #expect(lists.cached.isEmpty && log.published == [["own.example", "ads.example"]], "only Cra's own list, handed over once")

        log.pages[a] = .success(Data("0.0.0.0 alpha.example\n".utf8))
        lists.fetch(a)
        await lists.settle()
        #expect(lists.failures[a] == nil && log.published.last == ["own.example", "ads.example", "alpha.example"], "Try Again")
    }

    @Test func addingAndRemovingChangesWhatsBlocked() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualScheduler()
        log.pages[a] = .success(Data("alpha.example\n".utf8))
        log.pages[b] = .success(Data("beta.example\n".utf8))
        let lists = store()
        lists.set(addresses: [a], clock: clock)
        await lists.settle()
        lists.set(addresses: [a, b], clock: clock)
        await lists.settle()
        #expect(log.downloads == [a, b] && log.published.last == ["own.example", "ads.example", "alpha.example", "beta.example"])

        let publishes = log.published.count
        lists.set(addresses: [a, b], clock: clock)
        await lists.settle()
        #expect(log.published.count == publishes, "the same lists aren't handed over again")

        lists.set(addresses: [b], clock: clock)
        await lists.settle()
        #expect(lists.cached[a] == nil && log.published.last == ["own.example", "ads.example", "beta.example"])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(CustomBlocklist.cacheFileName(for: a)).path), "its copy is forgotten")
    }

    @Test func refetchesAWeekOldListWhileRunning() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualScheduler()
        try keep(a, domains: ["kept.example"], fetched: clock.now)
        log.pages[a] = .success(Data("fresh.example\n".utf8))
        let lists = store()
        lists.set(addresses: [a], clock: clock)
        await lists.settle()
        #expect(log.downloads.isEmpty)
        clock.advance(by: 2 * 24 * 3600)
        await lists.settle()
        #expect(log.downloads.isEmpty, "a day old is due only at launch")
        clock.advance(by: 5 * 24 * 3600)
        await lists.settle()
        #expect(log.downloads == [a] && lists.cached[a]?.domains == ["fresh.example"])
    }

    @Test func readsAChosenFile() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("hosts")
        try Data("127.0.0.1 localhost\n0.0.0.0 tracker.example\n".utf8).write(to: file)
        let lists = store()
        lists.set(addresses: [file.absoluteString], clock: ManualScheduler())
        await lists.settle()
        #expect(log.downloads.isEmpty, "a file isn't downloaded")
        #expect(lists.cached[file.absoluteString]?.domains == ["tracker.example"])
        #expect(BlocklistRow.name(file.absoluteString, cached: nil) == "hosts")
    }

    @Test func readsTextTheWayTheMacDid() {
        #expect(BlocklistStore.text(from: Data("a.example".utf8)) == .success("a.example"))
        #expect(BlocklistStore.text(from: Data([0x63, 0x61, 0x66, 0xE9])) == .success("café"), "Latin-1 when it isn't UTF-8")
        #expect(BlocklistStore.text(from: Data(count: BlocklistStore.maxBytes + 1)) == .failure(.tooBig))
        #expect(BlocklistStore.logName("https://lists.example/secret?token=1") == "lists.example")
        #expect(BlocklistStore.logName("file:///C:/lists/hosts") == "file")
    }

    @Test func rowsSayWhatEachListDoes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BlocklistRow.name(a, cached: nil) == "lists.example")
        #expect(BlocklistRow.status(cached: nil, failure: nil, now: now) == .fetching)
        #expect(BlocklistRow.status(cached: nil, failure: "nope", now: now) == .failed("nope"))
        let list = CachedBlocklist(url: a, list: ParsedBlocklist(text: "a.example\nb.example\n"), fetched: now.addingTimeInterval(-7200))
        #expect(BlocklistRow.status(cached: list, failure: nil, now: now) == .fetched("2 domains · Updated 2 hours ago"))
        #expect(BlocklistRow.status(cached: list, failure: "down", now: now) == .failed("down"), "a failure shows over the kept copy")
        let ago = { (s: TimeInterval) in BlocklistRow.updated(now.addingTimeInterval(-s), now: now) }
        #expect([ago(5), ago(60), ago(600), ago(3600), ago(86_400), ago(3 * 86_400), ago(8 * 86_400), ago(21 * 86_400)]
                == ["now", "1 minute ago", "10 minutes ago", "1 hour ago", "yesterday", "3 days ago", "last week", "3 weeks ago"])
    }
}
