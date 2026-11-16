import Foundation

extension ChromiumLocale {
    /// Chromium's locale on Windows, from the `locales` folder next to Cra.exe ("en-US.pak",
    /// "en-GB.pak", "es-419.pak") and Windows' display languages, most wanted first ("de-DE").
    /// Without it CEF uses en-US whatever Windows is set to (`CefSettings.locale` is empty).
    ///
    /// The folder names Chromium's English "en-US" where the Mac framework calls it "en", so
    /// that file stands for plain English here: a bare "en" or an American English picks it,
    /// not "en-GB". Matching is `portableMatch`, as everywhere outside macOS. Nil when the
    /// folder holds no locales, which leaves CEF's en-US.
    public static func pick(localePaks: [String], preferredLanguages: [String]) -> String? {
        let gendered = ["_FEMININE", "_MASCULINE", "_NEUTER"]
        let candidates = localePaks
            .filter { $0.lowercased().hasSuffix(".pak") }
            .map { String($0.dropLast(4)).replacingOccurrences(of: "_", with: "-") }
            .filter { name in !gendered.contains { name.hasSuffix($0.replacingOccurrences(of: "_", with: "-")) } }
            .map { $0 == "en-US" ? "en" : $0 }
        guard !candidates.isEmpty else { return nil }
        let match = portableMatch(candidates, preferredLanguages)
        return match == "en" ? "en-US" : match
    }
}
