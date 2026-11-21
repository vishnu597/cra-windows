import CraCEF
import Foundation

/// Settings ▸ Privacy ▸ Block lists (#507): CraCore's BlocklistStore with the Mac's pieces. Lists
/// are kept in the data folder's Blocklists folder, fetched with URLSession, and the engine gets
/// Cra's own list (resources/blocklist) with every added list's domains as one set.
@MainActor
enum BlockLists {
    static let shared = BlocklistStore(environment: .init(
        folder: BlockLists.folder,
        bundled: {
            Bundle.main.path(forResource: "domains", ofType: "txt", inDirectory: "blocklist")
                .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        },
        download: BlockLists.download,
        publish: { CraCEFRuntime.setBlockedDomains($0) },
        log: { CraLog.note($0) }))

    static var folder: URL {
        let url = AppPaths.supportDir.appendingPathComponent("Blocklists", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated fileprivate static func download(_ url: URL) async -> Result<Data, BlockListError> {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("text/plain, */*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(.status(http.statusCode))
            }
            return .success(data)
        } catch {
            return .failure(.network)
        }
    }
}
