import CraCore
import Foundation
import Testing

/// Page translation on Windows (#310), where stock CEF has no translate API: the page goes
/// through Google Translate's website proxy, and Arc's popover reads a PageTranslation built here.
struct WindowsWebTranslateTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310")) func aPageGoesThroughTheProxyAndBack() {
        let url = "https://www.example-site.com/news/a?id=3#top"
        let proxied = WebTranslate.proxy(url, to: "en")
        #expect(proxied == "https://www-example--site-com.translate.goog/news/a?id=3&_x_tr_sl=auto&_x_tr_tl=en&_x_tr_hl=en&_x_tr_pto=wapp#top")
        #expect(proxied.flatMap(WebTranslate.original) == url)
        #expect(proxied.flatMap(WebTranslate.translatedLanguage) == "en")
        #expect(WebTranslate.proxy("https://lemonde.fr/", to: "en", from: "fr")?.contains("_x_tr_sl=fr") == true)

        let plain = WebTranslate.proxy("http://example.org/", to: "de")
        #expect(plain == "https://example-org.translate.goog/?_x_tr_sl=auto&_x_tr_tl=de&_x_tr_hl=de&_x_tr_pto=wapp&_x_tr_sch=http")
        #expect(plain.flatMap(WebTranslate.original) == "http://example.org/")
        #expect(WebTranslate.original("https://a----b-com.translate.goog/") == "https://a--b.com/", "a doubled - is a -")
        #expect(WebTranslate.original(url) == nil && WebTranslate.translatedLanguage(url) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310")) func onlyWhatTheProxyCanShow() {
        for url in ["file:///C:/a.html", "https://192.168.1.1/", "http://localhost:8080/", "https://example.com:8443/",
                    "cra://settings", "https://intranet/", "https://example-com.translate.goog/"] {
            #expect(WebTranslate.proxy(url, to: "en") == nil, "\(url)")
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310")) func languagesAsGoogleNamesThem() {
        #expect(WebTranslate.code("en-US") == "en")
        #expect(WebTranslate.code("pt_BR") == "pt")
        #expect(WebTranslate.code("zh") == "zh-CN")
        #expect(WebTranslate.code("zh-Hant-TW") == "zh-TW")
        #expect(WebTranslate.code("iw") == "he")
        #expect(WebTranslate.code("und") == nil && WebTranslate.code("") == nil && WebTranslate.code("x1") == nil)
        #expect(WebTranslate.target(preferredLanguages: ["fr-CA", "en-US"]) == "fr")
        #expect(WebTranslate.target(preferredLanguages: ["qq-QQ"]) == "en")
        #expect(WebTranslate.target(preferredLanguages: []) == "en")
        func said(_ v: String) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: ["result": ["type": "string", "value": v]]), as: UTF8.self)
        }
        #expect(WebTranslate.language(fromReply: said("de-DE")) == "de")
        #expect(WebTranslate.language(fromReply: said("")) == "")
        #expect(WebTranslate.language(fromReply: nil) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310")) func aForeignPageOffersTranslation() {
        let french = WebTranslate.state(url: "https://www.lemonde.fr/", pageLanguage: "fr", target: "en", neverSites: [])
        #expect(french.offersTranslation && !french.translated)
        #expect(french.prompt == "Translate this page to English?")
        #expect(!french.otherLanguages.contains("fr") && french.otherLanguages.contains("de"))
        #expect(!WebTranslate.state(url: "https://www.bbc.co.uk/", pageLanguage: "en", target: "en", neverSites: []).offersTranslation)
        #expect(!WebTranslate.state(url: "https://www.lemonde.fr/", pageLanguage: nil, target: "en", neverSites: []).offersTranslation,
                "not before the page says its language")
        #expect(!WebTranslate.state(url: "https://www.lemonde.fr/", pageLanguage: "", target: "en", neverSites: []).offersTranslation)
        let never = WebTranslate.state(url: "https://www.lemonde.fr/a", pageLanguage: "fr", target: "en", neverSites: ["lemonde.fr"])
        #expect(never.neverSite && !never.offersTranslation, "Never Translate This Site")
        #expect(WebTranslate.site("https://www-lemonde-fr.translate.goog/") == "lemonde.fr")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310")) func aTranslatedPageOffersShowOriginal() throws {
        let url = try #require(WebTranslate.proxy("https://www.lemonde.fr/", to: "en"))
        let t = WebTranslate.state(url: url, pageLanguage: "fr", target: "en", neverSites: ["lemonde.fr"], step: .translated)
        #expect(t.translated && t.offersTranslation, "a translated page can always go back")
        #expect(t.prompt == "Translated from French.")
        #expect(t.toast == "Translated to English")
        #expect(t.revertedToast == "Translated back to French")
        #expect(WebTranslate.state(url: url, pageLanguage: nil, target: "en", neverSites: []).source == "und")
    }

    @Test func theLanguageProbeOnlyReads() throws {
        let params = try #require(JSONSerialization.jsonObject(with: Data(WebTranslate.languageParams.utf8)) as? [String: Any])
        #expect(params["expression"] as? String == WebTranslate.languageScript)
        #expect(params["returnByValue"] as? Bool == true && params["userGesture"] as? Bool == false)
    }
}
