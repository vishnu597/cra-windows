import CraCEFWin
import CraCore
import Foundation
import WinUI

extension DownloadHistory {
    /// Pauses, resumes or cancels a download still in progress; Chromium's next report shows it
    /// (the Mac's DownloadHistory.control).
    func control(_ id: UInt32, _ action: CraDownloadControl) {
        if cra_cef_control_download(id, action) == 0 { print("Cra: download control: no download in progress by that id") }
    }

    /// Arc's Move to Trash: the file goes to the Recycle Bin, the row with it.
    func moveToRecycleBin(_ entry: Entry) {
        if cra_shell_recycle(entry.path) != 0 { hide(.finished(entry)) }
    }
}

/// A download row's context menu, in the list over the Library button and on Library ▸
/// Downloads alike (#272; the Mac's DownloadRowMenu). Which items show is CraCore's
/// `DownloadMenu`, in Windows' words; this performs them.
@MainActor
enum DownloadRowMenu {
    /// Refills `menu` for `row` (on opening, so a row that finished or paused since is right).
    static func fill(_ menu: MenuFlyout, for row: DownloadHistory.Listed, history: DownloadHistory = .shared) {
        menu.items.clear()
        let path: String
        switch row {
        case .finished(let e): path = e.path
        case .live(let l): path = l.path
        }
        let kind = DownloadMenu.Kind.of(fileName: row.name)
        let sections = DownloadMenu.sections(for: row, fileExists: { FileManager.default.fileExists(atPath: $0) })
        for (i, section) in sections.enumerated() {
            if i > 0 { menu.items.append(MenuFlyoutSeparator()) }
            for action in section {
                menu.items.append(UI.menuItem(DownloadMenu.windowsTitle(action, kind: kind, fileName: row.name)) {
                    switch (action, row) {
                    case (.open, _): Shell.open(path)
                    case (.copy, _): _ = cra_clipboard_set_file(path)
                    case (.showInFinder, _): Shell.showInFolder(path)
                    case (.pause, .live(let l)): history.control(l.id, CraDownloadControlPause)
                    case (.resume, .live(let l)): history.control(l.id, CraDownloadControlResume)
                    case (.cancel, .live(let l)): history.control(l.id, CraDownloadControlCancel)
                    case (.hide, _): history.hide(row)
                    case (.moveToTrash, .finished(let e)): history.moveToRecycleBin(e)
                    default: break
                    }
                })
            }
        }
    }
}
