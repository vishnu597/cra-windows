import Foundation

/// A site's icon for places that show a site Cra may never have opened (a boost on Library ▸
/// Boosts, a tab that never loaded, SiteIconQueue): read from its home page's `<link rel=icon>`
/// tags as a page's icon is (the largest it declares, bitmaps before SVG), then /favicon.ico.
public enum SiteIcon {
    /// Where to look, best first, from the page at `base`.
    public static func candidates(html: String, base: URL) -> [URL] {
        var links: [(url: URL, size: Int, svg: Bool)] = []
        var rest = Substring(html)
        while let open = rest.range(of: "<link", options: .caseInsensitive) {
            guard let close = rest.range(of: ">", range: open.upperBound..<rest.endIndex) else { break }
            let tag = String(rest[open.upperBound..<close.lowerBound])
            rest = rest[close.upperBound...]
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.split(separator: " ").contains(where: { $0 == "icon" || $0 == "apple-touch-icon" }),
                  let href = attribute("href", in: tag), let url = URL(string: decode(href), relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme ?? "") else { continue }
            let size = (attribute("sizes", in: tag) ?? "").split(separator: " ")
                .compactMap { Int($0.lowercased().split(separator: "x").first ?? "") }.max() ?? 0
            let svg = url.path.lowercased().hasSuffix(".svg") || attribute("type", in: tag)?.contains("svg") == true
            links.append((url, size, svg))
        }
        var out = links.enumerated().sorted { a, b in
            if a.element.svg != b.element.svg { return !a.element.svg }
            if a.element.size != b.element.size { return a.element.size > b.element.size }
            return a.offset < b.offset
        }.map(\.element.url)
        if let ico = URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL, !out.contains(ico) { out.append(ico) }
        return out
    }

    /// Whether the icon loader may request `url`, a candidate or a redirect, for the site at `origin`: an
    /// http(s) address, and one on the Mac or its local network only for a site that is local itself
    /// (a dev server's page may use its own), so a public page can't make Cra send requests into the LAN.
    public static func mayFetch(_ url: URL, for origin: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { return false }
        return !isLocal(host: host) || isLocal(host: origin.host ?? "")
    }

    /// The formats favicons come in, by ImageIO type identifier. Only these reach ImageIO's parsers from a
    /// site, not camera RAW, PSD or the dozens of others it reads.
    public static let imageTypes: Set<String> = [
        "public.png", "public.jpeg", "com.compuserve.gif", "com.microsoft.ico", "org.webmproject.webp", "com.microsoft.bmp",
    ]

    /// Whether a site's bytes may be read as an icon: in one of `imageTypes`, as ImageIO typed them, or
    /// SVG text, which ImageIO doesn't type.
    public static func isIcon(imageType: String?, data: Data) -> Bool {
        imageType.map(imageTypes.contains) ?? isSVG(data)
    }

    /// Whether a site's bytes are an SVG: after a BOM and whitespace, an `<svg` element, or an XML prolog with
    /// one in the first 4 KB. The loader reads only these and bitmaps, not a PDF that AppKit would also draw.
    public static func isSVG(_ data: Data) -> Bool {
        var head = Substring(String(decoding: data.prefix(4096), as: UTF8.self))
        if head.first == "\u{FEFF}" { head = head.dropFirst() }
        head = head.drop { $0.isWhitespace }
        func element(at i: Substring.Index) -> Bool {
            let rest = head[i...].dropFirst(4)
            return head[i...].hasPrefix("<svg") && (rest.first.map { $0.isWhitespace || $0 == ">" || $0 == "/" } ?? false)
        }
        if let first = head.indices.first, element(at: first) { return true }
        guard head.hasPrefix("<?xml") else { return false }
        var from = head.startIndex
        while let r = head.range(of: "<svg", range: from..<head.endIndex) {
            if element(at: r.lowerBound) { return true }
            from = r.upperBound
        }
        return false
    }

    /// Whether a request for the site at `origin` may go to a server at `addresses`, the numeric
    /// addresses its name resolved to: by name a host may look public (mayFetch) and still point into the
    /// Mac or its network, an intranet name or one a page aims at a router. Only a local site's may.
    public static func mayConnect(to addresses: [String], for origin: URL) -> Bool {
        isLocal(host: origin.host ?? "") || !addresses.contains { isLocal(host: $0) }
    }

    /// Whether `host` names the Mac itself or a machine on its network: localhost, an unqualified or
    /// `.local` name, and loopback, private, shared (100.64/10), link-local and unique-local addresses.
    public static func isLocal(host: String) -> Bool {
        var name = host.lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        while name.hasSuffix(".") { name.removeLast() }
        if name.contains(":") {
            // A resolved link-local address names its interface: fe80::1%en0.
            if let zone = name.firstIndex(of: "%") { name = String(name[..<zone]) }
            guard let b = ipv6Bytes(name) else { return false }
            if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return isLocal(v4: b[12...].reduce(0) { $0 << 8 | UInt32($1) }) }
            return b[0..<15].allSatisfy { $0 == 0 } && b[15] <= 1  // :: and ::1
                || b[0] & 0xfe == 0xfc  // fc00::/7
                || (b[0] == 0xfe && b[1] & 0xc0 == 0x80)  // fe80::/10
        }
        // inet_aton's forms too: the short and numeric ones URLSession connects to (127.1, 2130706433).
        if let a = ipv4Value(name) { return isLocal(v4: a) }
        return name == "localhost" || name.hasSuffix(".localhost") || name.hasSuffix(".local") || !name.contains(".")
    }

    /// The 16 bytes of an IPv6 address, nil for anything else. Windows' C library has no inet_aton,
    /// so both parsers are Swift, on every platform.
    static func ipv6Bytes(_ text: String) -> [UInt8]? {
        var head: [UInt16] = [], tail: [UInt16] = [], sawGap = false
        var rest = Substring(text)
        var v4: [UInt8] = []
        if let dot = rest.lastIndex(of: ":"), rest[rest.index(after: dot)...].contains(".") {
            let quad = rest[rest.index(after: dot)...].split(separator: ".", omittingEmptySubsequences: false)
            guard quad.count == 4 else { return nil }
            for q in quad {
                guard !q.isEmpty, q.count <= 3, q.allSatisfy(\.isASCII), let n = UInt8(q) else { return nil }
                v4.append(n)
            }
            rest = rest[...dot]
            if !rest.hasSuffix("::") { rest = rest.dropLast() }
        }
        if let gap = rest.range(of: "::") {
            sawGap = true
            let a = rest[..<gap.lowerBound], z = rest[gap.upperBound...]
            guard !z.contains("::") else { return nil }
            guard let h = groups(a), let t = groups(z) else { return nil }
            (head, tail) = (h, t)
        } else {
            guard let h = groups(rest) else { return nil }
            head = h
        }
        let total = head.count + tail.count + v4.count / 2
        guard sawGap ? total < 8 : total == 8 else { return nil }
        let words = head + Array(repeating: 0, count: 8 - total) + tail
        return words.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] } + v4
    }

    private static func groups(_ text: Substring) -> [UInt16]? {
        if text.isEmpty { return [] }
        var out: [UInt16] = []
        for g in text.split(separator: ":", omittingEmptySubsequences: false) {
            guard (1...4).contains(g.count), g.allSatisfy(\.isHexDigit), let n = UInt16(g, radix: 16) else { return nil }
            out.append(n)
        }
        return out
    }

    /// An IPv4 address in any form inet_aton reads: a, a.b, a.b.c or a.b.c.d, each part decimal,
    /// 0x hex or 0 octal, the last filling the bytes left.
    static func ipv4Value(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var values: [UInt64] = []
        for p in parts {
            let lower = p.lowercased()
            let (digits, radix): (Substring, Int) = lower.hasPrefix("0x") ? (Substring(lower.dropFirst(2)), 16)
                : (lower.count > 1 && lower.hasPrefix("0")) ? (Substring(lower.dropFirst()), 8) : (Substring(lower), 10)
            guard !digits.isEmpty || radix == 16, digits.allSatisfy(\.isASCII) else { return nil }
            guard let v = digits.isEmpty ? 0 : UInt64(digits, radix: radix), v <= UInt64(UInt32.max) else { return nil }
            values.append(v)
        }
        var out: UInt64 = 0
        for (i, v) in values.dropLast().enumerated() {
            guard v <= 0xff else { return nil }
            out |= v << (8 * (3 - UInt64(i)))
        }
        let last = values.last!
        guard last < (UInt64(1) << (8 * (5 - UInt64(values.count)))) else { return nil }
        return UInt32(out | last)
    }

    private static func isLocal(v4 a: UInt32) -> Bool {
        let ranges: [(UInt32, UInt32)] = [
            (0x0000_0000, 8), (0x0A00_0000, 8), (0x7F00_0000, 8), (0xA9FE_0000, 16),
            (0xAC10_0000, 12), (0xC0A8_0000, 16), (0x6440_0000, 10),
        ]
        return ranges.contains { net, bits in a >> (32 - bits) == net >> (32 - bits) }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?i)(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 { if let r = Range(m.range(at: i), in: tag) { return String(tag[r]) } }
        return nil
    }

    private static func decode(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&") }
}
