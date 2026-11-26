import Foundation

/// A PNG file from pixels, for platforms whose toolkit has no encoder at hand (the Windows shell
/// keeps a custom tab icon as a PNG in the Favicons folder, as the Mac does). Straight RGBA, 8 bits
/// a channel, no filtering, the image data in stored (uncompressed) deflate blocks: a valid file
/// any decoder reads, a little bigger than a compressed one, which an icon can afford.
public enum PNGFile {
    /// `rgba` is `width * height * 4` bytes, top row first, alpha not premultiplied.
    public static func encode(rgba: [UInt8], width: Int, height: Int) -> Data? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(bigEndian: UInt32(width))
        header.append(bigEndian: UInt32(height))
        header.append(contentsOf: [8, 6, 0, 0, 0])  // 8-bit RGBA, deflate, no filter, no interlace
        chunk("IHDR", header, into: &out)
        // Each row starts with its filter type (0, none).
        var raw = [UInt8]()
        raw.reserveCapacity((width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0)
            raw.append(contentsOf: rgba[(y * width * 4)..<((y + 1) * width * 4)])
        }
        chunk("IDAT", zlibStored(raw), into: &out)
        chunk("IEND", Data(), into: &out)
        return out
    }

    /// Premultiplied BGRA (a XAML WriteableBitmap's, CraCEFWin's CraImage) as straight RGBA.
    public static func rgba(fromPremultipliedBGRA bgra: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count - 3, by: 4) {
            let a = Int(bgra[i + 3])
            func straight(_ v: UInt8) -> UInt8 { a == 0 ? 0 : UInt8(min(255, (Int(v) * 255 + a / 2) / a)) }
            out[i] = straight(bgra[i + 2])
            out[i + 1] = straight(bgra[i + 1])
            out[i + 2] = straight(bgra[i])
            out[i + 3] = UInt8(a)
        }
        return out
    }

    private static func chunk(_ type: String, _ body: Data, into out: inout Data) {
        out.append(bigEndian: UInt32(body.count))
        let typed = Data(type.utf8) + body
        out.append(typed)
        out.append(bigEndian: crc32(typed))
    }

    /// A zlib stream of stored blocks, at most 65 535 bytes each.
    static func zlibStored(_ bytes: [UInt8]) -> Data {
        var out = Data([0x78, 0x01])
        var start = 0
        repeat {
            let n = min(65_535, bytes.count - start)
            let last = start + n >= bytes.count
            out.append(last ? 1 : 0)
            out.append(UInt8(n & 0xFF))
            out.append(UInt8(n >> 8))
            out.append(UInt8(~n & 0xFF))
            out.append(UInt8((~n >> 8) & 0xFF))
            out.append(contentsOf: bytes[start..<(start + n)])
            start += n
        } while start < bytes.count
        out.append(bigEndian: adler32(bytes))
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes {
            a = (a + UInt32(v)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
    }
}

private extension Data {
    mutating func append(bigEndian v: UInt32) {
        append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
}
