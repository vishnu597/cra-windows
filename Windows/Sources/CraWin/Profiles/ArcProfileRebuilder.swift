import CraCore
import Foundation

/// Settings ▸ Profiles ▸ Rebuild from Arc… and the command bar's Rebuild Profiles from Arc… (the
/// Mac's ArcProfileRebuilder, GitHub #131): spaces that sit on Default while Arc has them on a
/// profile of their own go back on that profile (`SidebarStore.arcProfileMoves`), and those Arc
/// profiles' passwords and sign-ins are staged for the next start, as an import's are. Windows
/// doesn't restart for it, and its extensions load in every profile (stock CEF), so the
/// extensions stay as they are. The sheets' words are CraCore's (`ArcProfileRebuild`).
@MainActor
enum ArcProfileRebuilder {
    /// Shows a sheet; its completion gets the picked button, nil without one.
    typealias Present = (AppDialog, @escaping (Int?) -> Void) -> Void

    private static var folders: WindowsImportSource.Folders? {
        WindowsImportSource.Folders(environment: ProcessInfo.processInfo.environment)
    }

    private static var arc: WindowsImportSource? { WindowsImportSource.all.first { $0.kind == .arc } }

    /// Offered only while Arc's sidebar is on this PC.
    static var isAvailable: Bool {
        guard let folders, let arc else { return false }
        return arc.isAvailable(in: folders)
    }

    static func run(store: SidebarStore, present: @escaping Present) {
        guard isAvailable else { return present(AppDialog(ArcProfileRebuild.arcMissing)) { _ in } }
        guard let folders, let arc,
              let plan = try? arc.plan(in: folders, sqlite: { file, query in SQLiteSnapshot(copying: file)?.rows(query) ?? [] }) else {
            return present(AppDialog(ArcProfileRebuild.unreadable)) { _ in }
        }
        let moves = store.arcProfileMoves(plan)
        guard !moves.isEmpty else { return present(AppDialog(ArcProfileRebuild.nothingToMove)) { _ in } }
        present(AppDialog(ArcProfileRebuild.confirmation(moves, on: .windows))) { picked in
            guard picked == 0 else { return }
            let wanted = Set(moves.map(\.folder))
            let profiles = arc.profiles(in: folders).filter { wanted.contains($0.id) }
            let read = arc.userData(in: folders).map { CredentialImport.read(userData: $0, profiles: profiles) }
            let map = store.applyArcProfileMoves(moves)
            print("rebuild from Arc: moved \(moves.count) space(s), \(read?.credentials.cookies.count ?? 0) cookies, \(read?.credentials.logins.count ?? 0) passwords")
            let report = read?.report ?? CredentialImportReport()
            if let read, !CredentialImport.stage(read.credentials, profiles: map) {
                return present(AppDialog(ArcProfileRebuild.signInsNotSaved)) { _ in }
            }
            present(AppDialog(ArcProfileRebuild.moved(moves.count, credentials: report.summary(from: "Arc")))) { _ in }
        }
    }
}
