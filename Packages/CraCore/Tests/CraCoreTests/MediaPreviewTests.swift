#if canImport(CoreGraphics)
import CoreGraphics
#endif
import CraCore
import Foundation
import Testing

/// Arc's preview for a pick in Library ▸ Media, measured on Victor's Arc (8 Nov 2026).
struct MediaPreviewTests {
    @Test func thePanelSitsWhereArcsDid() {
        let p = MediaPreview.panel(in: CGRect(x: 0, y: 0, width: 1728, height: 1084))
        #expect(p == CGRect(x: 199, y: 133, width: 1330, height: 818))
    }

    @Test func thePictureFitsUnderTheHeader() {
        let panel = CGRect(x: 199, y: 133, width: 1330, height: 818)
        // Arc's square picture: 739 pt tall under the 46 pt header, centred across.
        let r = MediaPreview.media(CGSize(width: 1024, height: 1024), in: panel)
        #expect(r.height == 742.0)
        #expect(r.width == r.height)
        #expect(abs(r.midX - panel.midX) <= 0.5)
        #expect(r.minY == 148.0)
        // A wide one fills the width instead.
        let wide = MediaPreview.media(CGSize(width: 4000, height: 1000), in: panel)
        #expect(wide.width == 1300.0)
    }

    @Test func arrowsStopAtTheEnds() {
        #expect(MediaPreview.step(0, by: -1, count: 3) == nil)
        #expect(MediaPreview.step(0, by: 1, count: 3) == 1)
        #expect(MediaPreview.step(2, by: 1, count: 3) == nil)
    }

    @Test func theHeadersAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(MediaPreview.age(now.addingTimeInterval(-86_400), now: now) == "1 day ago")
        #expect(MediaPreview.age(now.addingTimeInterval(-10), now: now) == "Just now")
    }

    @Test func theOpenButtonNamesTheFilesApp() {
        #expect(MediaPreview.openTitle(app: "Photos") == "Open in Photos")
        #expect(MediaPreview.openTitle(app: nil) == "Open")
        #expect(MediaPreview.openTitle(app: "  ") == "Open")
    }

    @Test func keysCloseOrStep() {
        #expect(MediaPreview.action(for: .escape, isVideo: true) == .close)
        #expect(MediaPreview.action(for: .left, isVideo: false) == .step(-1))
        #expect(MediaPreview.action(for: .right, isVideo: false) == .step(1))
        // Space closes a picture, as Quick Look; a video keeps it.
        #expect(MediaPreview.action(for: .space, isVideo: false) == .close)
        #expect(MediaPreview.action(for: .space, isVideo: true) == nil)
    }

    @Test func hidingShowsTheNextOne() {
        let now = Date(timeIntervalSince1970: 0)
        let files = ["a.png", "b.png", "c.png"].map { MediaLibrary.File(path: "/m/\($0)", date: now) }
        let middle = MediaPreview.hiding(1, from: files)
        #expect(middle?.files.map(\.name) == ["a.png", "c.png"])
        #expect(middle?.index == 1)
        // The last one hidden: the one before it shows.
        #expect(MediaPreview.hiding(2, from: files)?.index == 1)
        // The only one hidden: the preview closes.
        #expect(MediaPreview.hiding(0, from: [files[0]]) == nil)
    }
}
