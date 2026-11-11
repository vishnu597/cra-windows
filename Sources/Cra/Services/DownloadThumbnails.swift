import AppKit
import CraCEF
import Observation
import QuickLookThumbnailing

extension DownloadHistory {
    static let shared = DownloadHistory(file: JSONStore("downloads.json"))

    /// Quick Look thumbnails by path, made on demand (DownloadThumbnails).
    var thumbnails: [String: NSImage] { DownloadThumbnails.shared.images }

    func thumbnail(for path: String) -> NSImage? { DownloadThumbnails.shared.thumbnail(for: path) }

    /// Pauses, resumes or cancels a download still in progress; Chromium's next report shows it.
    func control(_ id: UInt32, _ action: CraDownloadControl) {
        guard CraCEFRuntime.controlDownload(id, action: action) else {
            CraLog.note("download control: no download in progress by that id")
            return
        }
        CraLog.note("download control: \(["pause", "resume", "cancel"][action.rawValue])")
    }

    /// Arc's Move to Trash: the file goes to the Bin, the row with it.
    func moveToTrash(_ entry: Entry) {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: entry.path)]) { [weak self] _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.hide(.finished(entry)) } }
        }
    }
}

/// The downloads list's Quick Look thumbnails, by path.
@MainActor
@Observable
final class DownloadThumbnails {
    static let shared = DownloadThumbnails()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func thumbnail(for path: String) -> NSImage? {
        if let image = images[path] { return image }
        load(path)
        return nil
    }

    private func load(_ path: String) {
        guard !loading.contains(path) else { return }
        loading.insert(path)
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 40, height: 40),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            let image = thumbnail?.nsImage
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(path)
                self.images[path] = image ?? NSWorkspace.shared.icon(forFile: path)
            }
        }
    }
}
