import Foundation

/// Page translation where the engine has none of its own (Windows' stock CEF, without the Mac's
/// `translate-ui.patch`): the page is shown through Google Translate's website proxy
/// (`<host>.translate.goog`), the service Chromium's own translation calls, and Show Original
/// goes back to its address. Arc's button, popover and toasts are drawn from a `PageTranslation`
/// built here, so both apps word them the same (GitHub #310).
public enum WebTranslate {
    /// The proxy's domain.
    public static let proxyDomain = "translate.goog"

    /// The languages the popover's "Choose Another Language" lists (Google Translate's codes).
    public static let languages = [
        "af", "ar", "bg", "bn", "ca", "cs", "cy", "da", "de", "el", "en", "es", "et", "fa", "fi", "fil", "fr",
        "ga", "gu", "he", "hi", "hr", "hu", "id", "is", "it", "ja", "kn", "ko", "lt", "lv", "ml", "mr", "ms",
        "nl", "no", "pa", "pl", "pt", "ro", "ru", "sk", "sl", "sq", "sr", "sv", "sw", "ta", "te", "th", "tr",
        "uk", "ur", "vi", "zh-CN", "zh-TW",
    ]

    /// A language tag as Google Translate names it: its primary subtag, lower-cased, but Chinese
    /// keeps its script ("zh-Hant", "zh-TW" and "zh-HK" are Traditional), and old codes take
    /// their new names. nil for none, or for "und" and other non-languages.
    public static func code(_ tag: String) -> String? {
        let parts = tag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map { $0.lowercased() }
        guard let primary = parts.first, (2...3).contains(primary.count), primary.allSatisfy(\.isLetter),
              !["und", "mul", "zxx"].contains(primary) else { return nil }
        switch primary {
        case "zh":
            let traditional = parts.dropFirst().contains { ["hant", "tw", "hk", "mo"].contains($0) }
            return traditional ? "zh-TW" : "zh-CN"
        case "iw": return "he"
        case "tl": return "fil"
        case "nb", "nn": return "no"
        case "in": return "id"
        default: return primary
        }
    }

    /// The language pages are translated to: the first of the user's languages Google
    /// translates to, else English.
    public static func target(preferredLanguages: [String]) -> String {
        preferredLanguages.lazy.compactMap(code).first { languages.contains($0) } ?? "en"
    }

    // MARK: Addresses

    /// The page's address through the proxy, translated from `source` ("auto": Google detects
    /// it) to `target`. nil for what the proxy can't show: not http(s), an IP address,
    /// localhost, a port, or a page already on the proxy.
    public static func proxy(_ url: String, to target: String, from source: String = "auto") -> String? {
        guard let c = URLComponents(string: url), let scheme = c.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = c.host?.lowercased(), host.contains("."), c.port == nil, c.user == nil,
              !isProxy(host: host), !host.allSatisfy({ $0.isNumber || $0 == "." }), !host.contains(":") else { return nil }
        var out = URLComponents()
        out.scheme = "https"
        // Google's form: each - doubled, then each . a -.
        out.host = host.replacingOccurrences(of: "-", with: "--").replacingOccurrences(of: ".", with: "-") + "." + proxyDomain
        out.percentEncodedPath = c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath
        var items = (c.queryItems ?? []).filter { !$0.name.hasPrefix("_x_tr_") }
        items += [URLQueryItem(name: "_x_tr_sl", value: source), URLQueryItem(name: "_x_tr_tl", value: target),
                  URLQueryItem(name: "_x_tr_hl", value: target), URLQueryItem(name: "_x_tr_pto", value: "wapp")]
        if scheme == "http" { items.append(URLQueryItem(name: "_x_tr_sch", value: "http")) }
        out.queryItems = items
        out.percentEncodedFragment = c.percentEncodedFragment
        return out.string
    }

    /// The page a proxy address shows, nil for an address that isn't the proxy's.
    public static func original(_ url: String) -> String? {
        guard let c = URLComponents(string: url), let host = c.host?.lowercased(), isProxy(host: host) else { return nil }
        let label = String(host.dropLast(proxyDomain.count + 1))
        guard !label.isEmpty, !label.contains(".") else { return nil }
        // "--" was a -, each other - a .
        let original = label.components(separatedBy: "--").map { $0.replacingOccurrences(of: "-", with: ".") }.joined(separator: "-")
        var out = URLComponents()
        out.scheme = c.queryItems?.first { $0.name == "_x_tr_sch" }?.value ?? "https"
        out.host = original
        out.percentEncodedPath = c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath
        let items = (c.queryItems ?? []).filter { !$0.name.hasPrefix("_x_tr_") }
        out.queryItems = items.isEmpty ? nil : items
        out.percentEncodedFragment = c.percentEncodedFragment
        return out.string
    }

    /// The language a proxy address translates to.
    public static func translatedLanguage(_ url: String) -> String? {
        guard original(url) != nil else { return nil }
        return URLComponents(string: url)?.queryItems?.first { $0.name == "_x_tr_tl" }?.value.flatMap(code)
    }

    private static func isProxy(host: String) -> Bool { host.hasSuffix("." + proxyDomain) }

    /// The site Never Translate This Site names: the page's host without "www.", the original's
    /// on a translated page.
    public static func site(_ url: String) -> String? {
        guard let host = URLComponents(string: original(url) ?? url)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: The page's language

    /// Run in the page once it has loaded: the language it says it is in (`<html lang>`, else
    /// its Content-Language), "" for none.
    public static let languageScript = """
    (() => document.documentElement.lang
      || document.querySelector('meta[http-equiv="content-language" i]')?.content?.split(',')[0]
      || '')()
    """

    /// The DevTools `Runtime.evaluate` parameters for `languageScript`.
    public static var languageParams: String {
        let params: [String: Any] = ["expression": languageScript, "returnByValue": true, "userGesture": false]
        let data = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The page's answer: its language's code, "" when it names none, nil without an answer.
    public static func language(fromReply reply: String?) -> String? {
        guard let data = reply?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["exceptionDetails"] == nil,
              let value = (json["result"] as? [String: Any])?["value"] as? String else { return nil }
        return code(value) ?? ""
    }

    // MARK: The state

    /// The translate state for a page at `url`: `pageLanguage` is what the page said it is in
    /// (nil: not asked yet); on a translated page, the language the original was in, which the
    /// window kept when it translated. A translated page offers Show Original; another offers to translate
    /// when its language is known, isn't the target's and Google translates it, and the site
    /// isn't on the never list. `step` is what just happened, for the toast.
    public static func state(url: String, pageLanguage: String?, target: String, neverSites: Set<String>,
                             step: PageTranslation.Step? = nil) -> PageTranslation {
        if let to = translatedLanguage(url) {
            let asked = URLComponents(string: url)?.queryItems?.first { $0.name == "_x_tr_sl" }?.value.flatMap(code)
            let from = (pageLanguage ?? asked).flatMap { $0.isEmpty || $0 == to ? nil : $0 } ?? "und"
            return PageTranslation(url: url, source: from, current: to, target: to, available: true, translated: true,
                                   step: step, userGesture: step != nil, languages: languages)
        }
        let source = pageLanguage.flatMap { $0.isEmpty ? nil : $0 } ?? "und"
        let never = site(url).map { neverSites.contains($0) } ?? false
        let available = source != "und" && source != target && languages.contains(source) && proxy(url, to: target) != nil
        return PageTranslation(url: url, source: source, current: source, target: target, available: available,
                               neverSite: never, step: step, userGesture: step != nil, languages: languages)
    }
}
