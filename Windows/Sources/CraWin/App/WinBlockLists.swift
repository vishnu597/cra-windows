import CraCEFWin
import CraCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Settings ▸ Privacy ▸ Block lists (#507): CraCore's BlocklistStore with Windows' pieces, as
/// BlockLists is on the Mac. Copies are kept in %LOCALAPPDATA%\Cra\Blocklists, lists come over
/// FoundationNetworking, and the engine gets Cra's own list (blocklist\domains.txt beside Cra.exe)
/// with every added list's domains in one go (cra_cef_set_blocked_domains).
@MainActor
enum WinBlockLists {
    static let shared = BlocklistStore(environment: .init(
        folder: WinPaths.supportDir.appendingPathComponent("Blocklists", isDirectory: true),
        bundled: {
            let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            return try? String(contentsOf: exe.appendingPathComponent("blocklist").appendingPathComponent("domains.txt"), encoding: .utf8)
        },
        download: WinBlockLists.download,
        publish: { domains in cra_cef_set_blocked_domains(domains.joined(separator: "\n")) },
        log: { print("Cra: \($0)") }))

    /// No cookies, and no cache: a list is fetched fresh each time it's due.
    nonisolated private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    nonisolated fileprivate static func download(_ url: URL) async -> Result<Data, BlockListError> {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("text/plain, */*", forHTTPHeaderField: "Accept")
        return await withCheckedContinuation { (done: CheckedContinuation<Result<Data, BlockListError>, Never>) in
            session.dataTask(with: request) { data, response, error in
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    done.resume(returning: .failure(.status(http.statusCode)))
                } else if let data, error == nil {
                    done.resume(returning: .success(data))
                } else {
                    done.resume(returning: .failure(.network))
                }
            }.resume()
        }
    }
}
