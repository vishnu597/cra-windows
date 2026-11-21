import CraCore
import Foundation
import Testing

/// Arc's per-profile Download location (#190) and the name a download is saved as.
struct DownloadLocationTests {
    let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/190")) func profilesWithoutAChoiceUseDownloadsWithoutAsking() {
        let s = AppSettings()
        #expect(s.downloadLocation(profileID: nil) == DownloadLocation())
        #expect(s.downloadLocation(profileID: UUID()).folderURL(downloads: downloads) { _ in true } == downloads)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/190")) func eachProfileKeepsItsOwn() throws {
        var s = AppSettings()
        let work = UUID()
        s.setDownloadLocation(DownloadLocation(folder: "/Volumes/Work", askWhereToSave: false), profileID: work)
        s.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        #expect(s.downloadLocation(profileID: work).folder == "/Volumes/Work")
        #expect(s.downloadLocation(profileID: nil).askWhereToSave)
        #expect(s.downloadLocation(profileID: UUID()) == DownloadLocation())
        // Saved and loaded again.
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.downloadLocations == s.downloadLocations)
        #expect(Set(back.downloadLocations.keys) == [work.uuidString, "Default"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/190")) func goingBackToTheDefaultDropsTheEntry() {
        var s = AppSettings()
        s.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        s.setDownloadLocation(DownloadLocation(), profileID: nil)
        #expect(s.downloadLocations.isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/190")) func aMissingFolderFallsBackToDownloads() {
        let l = DownloadLocation(folder: "/Volumes/Unplugged")
        #expect(l.folderURL(downloads: downloads) { _ in false } == downloads)
        #expect(l.folderURL(downloads: downloads) { _ in true }.path == "/Volumes/Unplugged")
    }

    @Test func aRelativeFolderInTheFileIsIgnored() throws {
        let json = #"{"downloadLocations": {"Default": {"folder": "../etc", "askWhereToSave": true}, "x": 3}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        // A bad entry drops the whole map rather than the settings file.
        #expect(s.downloadLocations.isEmpty)
        let one = try JSONDecoder().decode(DownloadLocation.self, from: Data(#"{"folder": "../etc"}"#.utf8))
        #expect(one.folder == nil && !one.askWhereToSave)
    }

    @Test(arguments: [
        ("report.pdf", "report.pdf"),
        ("../../.ssh/config", "-..-.ssh-config"),
        (".hidden", "hidden"),
        ("a:b/c.txt", "a-b-c.txt"),
        ("   ", "download"),
        ("", "download"),
    ])
    func names(suggested: String, saved: String) {
        let url = DownloadFileName.unique(suggested, in: downloads) { _ in false }
        #expect(url.lastPathComponent == saved)
        #expect(url.deletingLastPathComponent().path == downloads.path)
    }

    @Test func takenNamesGetANumber() {
        let taken: Set = ["/Users/me/Downloads/a.zip", "/Users/me/Downloads/a (1).zip", "/Users/me/Downloads/README"]
        #expect(DownloadFileName.unique("a.zip", in: downloads) { taken.contains($0) }.lastPathComponent == "a (2).zip")
        #expect(DownloadFileName.unique("README", in: downloads) { taken.contains($0) }.lastPathComponent == "README (1)")
    }

    // Windows (PARITY "Download location per profile"): drive and share folders are absolute
    // there, so a Windows settings.json keeps them; relative ones are still dropped.
    @Test(arguments: [
        (#"C:\Users\me\Downloads"#, true),
        ("D:/Work", true),
        (#"\\nas\share\in"#, true),
        ("/Volumes/Work", true),
        ("C:foo", false),
        (#"\\?\C:\x"#, false),
        (#"\\"#, false),
        ("../etc", false),
        ("Downloads", false),
        ("", false),
    ] as [(String, Bool)])
    func absoluteFolders(path: String, kept: Bool) throws {
        #expect(DownloadLocation.isAbsolute(path) == kept)
        let json = try JSONEncoder().encode(["folder": path])
        let decoded = try JSONDecoder().decode(DownloadLocation.self, from: json)
        #expect(decoded.folder == (kept ? path : nil))
    }

    @Test func folderNames() {
        #expect(DownloadLocation().folderName == "Downloads")
        #expect(DownloadLocation(folder: #"C:\Users\me\Saved\"#).folderName == "Saved")
        #expect(DownloadLocation(folder: "/Volumes/Work").folderName == "Work")
        #expect(DownloadLocation(folder: #"D:\"#).folderName == "D:")
    }

    @Test func theWindowsBridgeGetsEachProfilesChromiumFolder() {
        var s = AppSettings()
        let work = BrowserProfile(id: UUID(), name: "Work")
        s.setDownloadLocation(DownloadLocation(folder: #"D:\Work\In"#), profileID: work.id)
        s.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        // A profile deleted since: nothing to look up.
        s.setDownloadLocation(DownloadLocation(folder: #"E:\Gone"#), profileID: UUID())
        let lines = DownloadLocation.bridgeLines(s.downloadLocations, profiles: [work]).split(separator: "\n").map(String.init)
        #expect(Set(lines) == ["Default\t\t1", "\(work.directoryName)\tD:\\Work\\In\t0"])
        #expect(DownloadLocation.bridgeLines([:], profiles: [work]).isEmpty)
    }

    @Test func pickingTheDownloadsFolderGoesBackToTheDefault() {
        let downloads = #"C:\Users\me\Downloads"#
        #expect(DownloadLocation.picked(#"c:\users\me\downloads\"#, downloads: downloads) == nil)
        #expect(DownloadLocation.picked(#"D:\In"#, downloads: downloads) == #"D:\In"#)
        #expect(DownloadLocation.picked(#"D:\In"#, downloads: nil) == #"D:\In"#)
    }
}
