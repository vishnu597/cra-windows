@testable import CraCore
import Foundation
import Testing

struct PNGFileTests {
    /// The chunks of a PNG file: type and body, each with its CRC checked.
    private func chunks(_ png: Data) -> [(type: String, body: [UInt8])]? {
        let bytes = [UInt8](png)
        guard bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else { return nil }
        func u32(_ i: Int) -> UInt32 { bytes[i..<(i + 4)].reduce(0) { $0 << 8 | UInt32($1) } }
        var out: [(String, [UInt8])] = []
        var i = 8
        while i + 12 <= bytes.count {
            let n = Int(u32(i))
            let typed = Data(bytes[(i + 4)..<(i + 8 + n)])
            guard PNGFile.crc32(typed) == u32(i + 8 + n) else { return nil }
            out.append((String(decoding: typed.prefix(4), as: UTF8.self), Array(typed.dropFirst(4))))
            i += 12 + n
        }
        return i == bytes.count ? out : nil
    }

    /// What a zlib stream of stored blocks holds, its Adler-32 checked.
    private func inflateStored(_ z: [UInt8]) -> [UInt8]? {
        guard z.count >= 6, (Int(z[0]) << 8 | Int(z[1])) % 31 == 0, z[0] & 0x0F == 8 else { return nil }
        var out: [UInt8] = [], i = 2
        while true {
            let final = z[i] & 1 == 1
            guard z[i] >> 1 == 0 else { return nil }
            let n = Int(z[i + 1]) | Int(z[i + 2]) << 8
            guard n == ~(Int(z[i + 3]) | Int(z[i + 4]) << 8) & 0xFFFF else { return nil }
            out += z[(i + 5)..<(i + 5 + n)]
            i += 5 + n
            if final { break }
        }
        let adler = z[i..<(i + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return adler == PNGFile.adler32(out) && i + 4 == z.count ? out : nil
    }

    @Test func checksumsMatchTheirKnownValues() {
        #expect(PNGFile.crc32(Data("IEND".utf8)) == 0xAE42_6082)
        #expect(PNGFile.adler32(Array("Wikipedia".utf8)) == 0x11E6_0398)
    }

    @Test func aPixelBecomesAWholeFile() throws {
        let png = try #require(PNGFile.encode(rgba: [255, 0, 0, 128], width: 1, height: 1))
        let parts = try #require(chunks(png))
        #expect(parts.map(\.type) == ["IHDR", "IDAT", "IEND"])
        #expect(parts[0].body == [0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0])
        #expect(inflateStored(parts[1].body) == [0, 255, 0, 0, 128])
        #expect(parts[2].body.isEmpty)
    }

    /// Rows past 64 KB of data take more than one stored block, each row led by filter 0.
    @Test func bigImagesSpanSeveralBlocks() throws {
        let width = 200, height = 100
        let rgba = (0..<(width * height * 4)).map { UInt8($0 % 251) }
        let png = try #require(PNGFile.encode(rgba: rgba, width: width, height: height))
        let parts = try #require(chunks(png))
        let raw = try #require(inflateStored(parts[1].body))
        #expect(raw.count == (width * 4 + 1) * height)
        for y in 0..<height {
            let row = y * (width * 4 + 1)
            #expect(raw[row] == 0)
            #expect(Array(raw[(row + 1)..<(row + 1 + width * 4)]) == Array(rgba[(y * width * 4)..<((y + 1) * width * 4)]))
        }
    }

    @Test func refusesPixelsThatDontFit() {
        #expect(PNGFile.encode(rgba: [1, 2, 3], width: 1, height: 1) == nil)
        #expect(PNGFile.encode(rgba: [], width: 0, height: 0) == nil)
    }

    /// Premultiplied BGRA (what Windows draws into) comes back to straight RGBA.
    @Test func premultipliedBGRABecomesStraightRGBA() {
        #expect(PNGFile.rgba(fromPremultipliedBGRA: [0, 0, 128, 128, 10, 20, 30, 255, 5, 5, 5, 0])
            == [255, 0, 0, 128, 30, 20, 10, 255, 0, 0, 0, 0])
    }
}
