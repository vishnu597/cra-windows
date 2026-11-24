import CraCore
import Foundation

/// Each tab's saved back and forward list (CraCore's PageList, GitHub #273), one file a tab in the
/// data folder's PageList/, so a navigation rewrites only its own tab's file. The Mac keeps its
/// engine's serialized navigations in PageHistory/ instead, which stock CEF can't restore.
@MainActor
final class PageListStore {
    static let shared = PageListStore()
    private let folder = WinPaths.supportDir.appendingPathComponent("PageList", isDirectory: true)
    /// What was saved this run.
    private var latest: [UUID: PageList] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".json") }

    func load(_ id: UUID) -> PageList? {
        if let list = latest[id] { return list }
        return (try? Data(contentsOf: file(id))).flatMap { try? JSONDecoder().decode(PageList.self, from: $0) }
    }

    func save(_ list: PageList, for id: UUID) {
        guard latest[id] != list else { return }
        latest[id] = list
        do {
            try JSONEncoder().encode(list).write(to: file(id), options: .atomic)
        } catch {
            print("Cra: tab \(id)'s back and forward list could not be saved: \(error)")
        }
    }

    /// Drops every file but `kept`'s (PageHistory.kept: the sidebar's tabs and the latest closed).
    func prune(keeping kept: Set<UUID>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            guard let id = UUID(uuidString: name.replacingOccurrences(of: ".json", with: "")), !kept.contains(id) else { continue }
            latest[id] = nil
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
