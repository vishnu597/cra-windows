import CraCEFWin
import CraCore
import Foundation
import Observation
import UWP
import WinAppSDK
import WinUI

/// Library ▸ Media's files (MediaLibrary, the Mac's MediaScanner): the folders read off the UI
/// thread, top level only, as Arc reads them, and Explorer's picture of each file.
@MainActor
@Observable
final class MediaScannerWin {
    static let shared = MediaScannerWin()

    private(set) var files: [MediaLibrary.File] = []
    /// Bumped as pictures arrive.
    private(set) var revision = 0
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var pending: [MediaLibrary.Folder]?
    @ObservationIgnored private var images: [String: WriteableBitmap] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    /// A tile is 132 DIPs: its picture fits 108, asked for at up to 300 % scaling.
    private static let side = 324

    /// Windows' folder for each of Arc's: Pictures ▸ Screenshots is where Win+Print Screen and
    /// the Snipping Tool save.
    nonisolated static func url(_ folder: MediaLibrary.Folder) -> URL? {
        let fm = FileManager.default
        switch folder {
        case .documents: return fm.urls(for: .documentDirectory, in: .userDomainMask).first
        case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .screenshots: return fm.urls(for: .picturesDirectory, in: .userDomainMask).first?.appendingPathComponent("Screenshots", isDirectory: true)
        }
    }

    func rescan(_ folders: [MediaLibrary.Folder]) {
        // One scan at a time; the folders asked for meanwhile are read next.
        guard !scanning else { pending = folders; return }
        scanning = true
        let urls = folders.compactMap(Self.url)
        let finished: @MainActor ([MediaLibrary.File]) -> Void = { [weak self] result in
            guard let self else { return }
            self.scanning = false
            if result != self.files { self.files = result }
            if let next = self.pending {
                self.pending = nil
                self.rescan(next)
            }
        }
        let done = UncheckedSendable(value: finished)
        let queue = UncheckedSendable(value: (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil)
        DispatchQueue.global(qos: .utility).async {
            var found: [MediaLibrary.File] = []
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            for dir in urls {
                let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                          options: [.skipsHiddenFiles])) ?? []
                for u in items where MediaLibrary.isMedia(u.path) {
                    let v = try? u.resourceValues(forKeys: Set(keys))
                    guard v?.isRegularFile == true else { continue }
                    found.append(.init(path: u.path, date: v?.contentModificationDate ?? .distantPast))
                }
            }
            let result = MediaLibrary.shown(found, query: "")
            _ = try? queue.value?.tryEnqueue { onMain { done.value(result) } }
        }
    }

    /// Explorer's picture of the file (a preview for a picture or a video), cached; nil until it
    /// is made, then `revision` changes.
    func thumbnail(_ file: MediaLibrary.File) -> WriteableBitmap? {
        let key = "\(file.path)|\(file.date.timeIntervalSince1970)"
        if let image = images[key] { return image }
        guard loading.insert(key).inserted, let dispatcher = (try? WinAppSDK.DispatcherQueue.getForCurrentThread()) ?? nil else { return nil }
        let queue = UncheckedSendable(value: dispatcher)
        let arrived: @MainActor (Pixels?) -> Void = { [weak self] pixels in
            guard let self, let image = pixels?.bitmap() else { return }
            self.images[key] = image
            self.revision += 1
        }
        let done = UncheckedSendable(value: arrived)
        let path = file.path, side = Self.side
        DispatchQueue.global(qos: .utility).async {
            let pixels = Pixels.file(path, side: side)
            _ = try? queue.value.tryEnqueue { onMain { done.value(pixels) } }
        }
        return nil
    }
}

/// Arc's Media grid (MediaGridMetrics on the Mac, Arc 1.172.1): two tiles a row, 132 DIPs high,
/// 12 in from the left and 16 apart, rows 8 apart; a faint fill (darker under the pointer) with
/// 10 DIP corners, the picture fitted 12 in, framed in 4 DIPs of white.
enum MediaGridWin {
    static let tile = 132.0
    static let inset = 12.0
    static let trailing = 13.0
    static let gap = 16.0
    static let rowGap = 8.0
    static let padding = 12.0
    static let frame = 4.0
}

/// Copying a picked file, as the Mac's MediaMenu does: the file itself, and for a PNG the
/// picture too.
enum MediaClipboard {
    @discardableResult
    static func copy(_ path: String) -> Bool {
        let png = path.lowercased().hasSuffix(".png") ? (try? Data(contentsOf: URL(fileURLWithPath: path))) : nil
        return path.withCString { p in
            guard let png else { return cra_clipboard_set_file(p, nil, 0) != 0 }
            return png.withUnsafeBytes { raw in
                cra_clipboard_set_file(p, raw.bindMemory(to: UInt8.self).baseAddress, raw.count) != 0
            }
        }
    }
}
