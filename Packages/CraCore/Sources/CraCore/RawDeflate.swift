import Foundation

/// Raw DEFLATE (RFC 1951, no zlib header or checksum): what Apple's
/// `NSData.compressed(using: .zlib)` writes and the share links carry (`FolderShareLink`,
/// `SharedBoost`). Apple's Foundation has the codec; the Windows and Linux Foundation don't,
/// so off Apple platforms Cra inflates with `inflate` here and deflates into stored blocks:
/// valid DEFLATE that every reader takes, only not smaller than the input.
public enum RawDeflate {
    /// The data packed, nil when it can't be.
    public static func compress(_ data: Data) -> Data? {
        #if canImport(Darwin)
        return try? (data as NSData).compressed(using: .zlib) as Data
        #else
        return stored(data)
        #endif
    }

    /// The data unpacked, nil for anything that isn't raw DEFLATE or would unpack past `limit`.
    public static func decompress(_ data: Data, limit: Int = 1 << 24) -> Data? {
        #if canImport(Darwin)
        guard let out = try? (data as NSData).decompressed(using: .zlib) as Data, out.count <= limit else { return nil }
        return out
        #else
        return inflate(data, limit: limit)
        #endif
    }

    /// The data as DEFLATE stored (uncompressed) blocks of at most 65,535 bytes.
    public static func stored(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 5 * (bytes.count / 65_535 + 1))
        var start = 0
        repeat {
            let end = min(bytes.count, start + 65_535)
            let length = end - start
            out.append(end == bytes.count ? 1 : 0)  // BFINAL, BTYPE 00
            out += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)]
            out += bytes[start..<end]
            start = end
        } while start < bytes.count
        return Data(out)
    }

    /// A raw DEFLATE stream unpacked in Swift (after zlib's puff.c), on every platform; nil for a
    /// broken stream or one that would unpack past `limit` bytes.
    public static func inflate(_ data: Data, limit: Int = 1 << 24) -> Data? {
        var inflater = Inflater(input: [UInt8](data), limit: limit)
        guard (try? inflater.run()) != nil else { return nil }
        return Data(inflater.out)
    }
}

private struct Inflater {
    struct Broken: Error {}

    struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        /// Canonical codes from code lengths; throws when the lengths over-subscribe.
        init(lengths: [Int]) throws {
            symbol = [Int](repeating: 0, count: lengths.count)
            for l in lengths { count[l] += 1 }
            var left = 1
            for len in 1..<16 {
                left <<= 1
                left -= count[len]
                if left < 0 { throw Broken() }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offsets[len + 1] = offsets[len] + count[len] }
            for (s, l) in lengths.enumerated() where l != 0 {
                symbol[offsets[l]] = s
                offsets[l] += 1
            }
        }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
                               2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    let input: [UInt8]
    let limit: Int
    var position = 0
    var bitBuffer: UInt32 = 0
    var bitCount = 0
    var out: [UInt8] = []

    init(input: [UInt8], limit: Int) {
        self.input = input
        self.limit = limit
    }

    mutating func bits(_ n: Int) throws -> Int {
        var value = bitBuffer
        while bitCount < n {
            guard position < input.count else { throw Broken() }
            value |= UInt32(input[position]) << UInt32(bitCount)
            position += 1
            bitCount += 8
        }
        bitBuffer = n == 32 ? 0 : value >> UInt32(n)
        bitCount -= n
        return Int(value & ((UInt32(1) << UInt32(n)) - 1))
    }

    mutating func run() throws {
        var last = false
        while !last {
            last = try bits(1) == 1
            switch try bits(2) {
            case 0: try storedBlock()
            case 1: try fixedBlock()
            case 2: try dynamicBlock()
            default: throw Broken()
            }
        }
    }

    mutating func storedBlock() throws {
        bitBuffer = 0
        bitCount = 0
        guard position + 4 <= input.count else { throw Broken() }
        let length = Int(input[position]) | Int(input[position + 1]) << 8
        let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
        position += 4
        guard length == ~complement & 0xFFFF, position + length <= input.count, out.count + length <= limit else { throw Broken() }
        out += input[position..<position + length]
        position += length
    }

    mutating func fixedBlock() throws {
        var lengths = [Int](repeating: 8, count: 288)
        for s in 144..<256 { lengths[s] = 9 }
        for s in 256..<280 { lengths[s] = 7 }
        try codes(Huffman(lengths: lengths), Huffman(lengths: [Int](repeating: 5, count: 30)))
    }

    mutating func dynamicBlock() throws {
        let literals = try bits(5) + 257
        let distances = try bits(5) + 1
        let codeLengths = try bits(4) + 4
        guard literals <= 286, distances <= 30 else { throw Broken() }
        var lengths = [Int](repeating: 0, count: 19)
        for i in 0..<codeLengths { lengths[Self.order[i]] = try bits(3) }
        let lengthCode = try Huffman(lengths: lengths)
        var all: [Int] = []
        while all.count < literals + distances {
            let symbol = try decode(lengthCode)
            if symbol < 16 {
                all.append(symbol)
                continue
            }
            var value = 0, repeats = 0
            switch symbol {
            case 16:
                guard let previous = all.last else { throw Broken() }
                value = previous
                repeats = 3 + (try bits(2))
            case 17: repeats = 3 + (try bits(3))
            default: repeats = 11 + (try bits(7))
            }
            guard all.count + repeats <= literals + distances else { throw Broken() }
            all += [Int](repeating: value, count: repeats)
        }
        guard all[256] != 0 else { throw Broken() }
        try codes(Huffman(lengths: Array(all[0..<literals])), Huffman(lengths: Array(all[literals...])))
    }

    mutating func decode(_ h: Huffman) throws -> Int {
        var code = 0, first = 0, index = 0
        for len in 1..<16 {
            code |= try bits(1)
            let count = h.count[len]
            if code - count < first { return h.symbol[index + (code - first)] }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw Broken()
    }

    mutating func codes(_ literal: Huffman, _ distance: Huffman) throws {
        while true {
            var symbol = try decode(literal)
            if symbol < 256 {
                guard out.count < limit else { throw Broken() }
                out.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { return }
            symbol -= 257
            guard symbol < 29 else { throw Broken() }
            let length = Self.lengthBase[symbol] + (try bits(Self.lengthExtra[symbol]))
            let d = try decode(distance)
            guard d < 30 else { throw Broken() }
            let back = Self.distanceBase[d] + (try bits(Self.distanceExtra[d]))
            guard back <= out.count, out.count + length <= limit else { throw Broken() }
            let start = out.count - back
            for i in 0..<length { out.append(out[start + i]) }
        }
    }
}
