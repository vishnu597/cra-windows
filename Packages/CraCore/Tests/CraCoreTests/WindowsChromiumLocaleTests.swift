import CraCore
import Testing

/// Chromium's language follows Windows' display language, from CEF's `locales/*.pak`.
struct WindowsChromiumLocaleTests {
    /// CEF 156's Windows `locales` folder (a sample, with a gendered variant).
    static let paks = ["af.pak", "af_FEMININE.pak", "da.pak", "de.pak", "en-GB.pak", "en-US.pak", "es.pak",
                       "es-419.pak", "nb.pak", "pt-BR.pak", "pt-PT.pak", "zh-CN.pak", "zh-TW.pak"]

    // Typed up front (the Mac type checker times out on untyped tuple literals).
    static let languages: [([String], String)] = [
        (["en-US"], "en-US"),
        // The folder's en-US is plain English: a bare "en" isn't British English.
        (["en"], "en-US"),
        (["en-IN"], "en-GB"),
        (["en-GB"], "en-GB"),
        (["de-DE"], "de"),
        (["zh-HK"], "zh-TW"),
        (["zh-Hans-CN"], "zh-CN"),
        (["es-MX"], "es-419"),
        (["pt-PT"], "pt-PT"),
        (["is-IS", "da-DK"], "da"),
        (["is-IS"], "en-US"),
        ([], "en-US"),
    ]

    @Test(arguments: languages)
    func followsWindows(preferred: [String], locale: String) {
        #expect(ChromiumLocale.pick(localePaks: Self.paks, preferredLanguages: preferred) == locale)
    }

    @Test func genderedVariantsAndOtherFilesAreNotLocales() {
        #expect(ChromiumLocale.pick(localePaks: ["af_FEMININE.pak", "readme.txt"], preferredLanguages: ["af"]) == nil)
        #expect(ChromiumLocale.pick(localePaks: [], preferredLanguages: ["de"]) == nil)
        #expect(ChromiumLocale.pick(localePaks: ["fr.pak", "de.pak"], preferredLanguages: ["is"]) == "fr")
    }
}
