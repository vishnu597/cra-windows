import CraCore
import Foundation
import Testing

/// Arc's "Block Cookie Banners": the consent managers' containers are hidden, nothing else.
struct CookieBannersTests {
    @Test(arguments: ["#onetrust-banner-sdk", "#CybotCookiebotDialog", "#didomi-host", ".qc-cmp2-container", "#usercentrics-root"])
    func hidesTheBigConsentManagers(selector: String) {
        #expect(CookieBanners.css.contains(selector))
    }

    @Test func hidesOnlyIdsClassesAndAttributes() {
        // No bare element selectors: they would hide parts of every page.
        for s in CookieBanners.selectors {
            #expect(s.hasPrefix("#") || s.hasPrefix(".") || s.hasPrefix("["), "\(s)")
        }
    }

    @Test func pageScriptAdoptsTheStylesheetUnchanged() throws {
        let script = CookieBanners.pageScript
        #expect(script.hasPrefix("(()=>{") && script.hasSuffix("})()"))
        #expect(script.contains("document.adoptedStyleSheets=[...document.adoptedStyleSheets,s]"))
        #expect(!script.contains("window."))
        // The stylesheet travels as a JSON string literal: read back, it is the CSS itself.
        let start = try #require(script.range(of: "s.replaceSync(")).upperBound
        let end = try #require(script.range(of: "[0]);", range: start..<script.endIndex)).lowerBound
        let decoded = try JSONSerialization.jsonObject(with: Data(script[start..<end].utf8)) as? [String]
        #expect(decoded == [CookieBanners.css])
    }
}
