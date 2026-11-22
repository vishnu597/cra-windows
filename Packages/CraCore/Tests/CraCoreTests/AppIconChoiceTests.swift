import CraCore
import Testing

struct AppIconChoiceTests {
    @Test func presetsAreCrasFourWithSegmentsFirst() {
        #expect(AppIconChoice.presets.map(\.id) == ["segments", "midnight", "mono", "violet"])
        #expect(AppIconChoice.presets.map(\.name) == ["Segments", "Midnight", "Mono", "Violet"])
        #expect(AppIconChoice.presets.first?.id == AppIconChoice.defaultID)
        #expect(AppIconChoice.storageKey == "appIcon")
    }

    @Test func storedChoiceResolves() {
        #expect(AppIconChoice.resolved(stored: nil, hasCustom: false) == "segments")
        #expect(AppIconChoice.resolved(stored: "violet", hasCustom: false) == "violet")
        #expect(AppIconChoice.resolved(stored: "custom", hasCustom: true) == "custom")
        #expect(AppIconChoice.resolved(stored: "custom", hasCustom: false) == "segments", "the image was removed")
        #expect(AppIconChoice.resolved(stored: "neon", hasCustom: true) == "segments", "a name this version doesn't know")
    }

    @Test func bundledFilesAreThePresetsPictures() {
        #expect(AppIconChoice.bundledFile("mono") == "app-icons/mono.png")
        #expect(AppIconChoice.bundledFile("custom") == nil)
        #expect(AppIconChoice.bundledFile("neon") == nil)
    }
}
