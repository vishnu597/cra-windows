import CraCore
import Testing

struct AppIconChoiceTests {
    /// Segments, Arc's icon set redrawn around Cra's C (upstream aa752f6e), then Cra's earlier alternates.
    @Test func presetsAreSegmentsThenArcsSetThenCrasAlternates() {
        #expect(AppIconChoice.presets.map(\.id) == ["segments", "original", "candy", "hologram", "neon", "fluted-glass", "schoolbook",
                                                     "colorful", "canary", "early-birds", "midnight", "mono", "violet"])
        #expect(AppIconChoice.presets.map(\.name) == ["Segments", "Original", "Candy", "Hologram", "Neon", "Fluted Glass", "Schoolbook",
                                                       "Colorful", "Canary", "Early Birds", "Midnight", "Mono", "Violet"])
        #expect(AppIconChoice.presets.first?.id == AppIconChoice.defaultID)
        #expect(AppIconChoice.storageKey == "appIcon")
    }

    @Test func storedChoiceResolves() {
        #expect(AppIconChoice.resolved(stored: nil, hasCustom: false) == "segments")
        #expect(AppIconChoice.resolved(stored: "violet", hasCustom: false) == "violet")
        #expect(AppIconChoice.resolved(stored: "custom", hasCustom: true) == "custom")
        #expect(AppIconChoice.resolved(stored: "custom", hasCustom: false) == "segments", "the image was removed")
        #expect(AppIconChoice.resolved(stored: "neon", hasCustom: false) == "neon")
        #expect(AppIconChoice.resolved(stored: "aurora", hasCustom: true) == "segments", "a name this version doesn't know")
    }

    @Test func bundledFilesAreThePresetsPictures() {
        #expect(AppIconChoice.bundledFile("mono") == "app-icons/mono.png")
        #expect(AppIconChoice.bundledFile("custom") == nil)
        #expect(AppIconChoice.bundledFile("neon") == "app-icons/neon.png")
        #expect(AppIconChoice.bundledFile("aurora") == nil)
    }
}
