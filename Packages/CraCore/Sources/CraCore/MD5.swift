import Foundation

/// MD5 (RFC 1321), for names other apps derive with it: Arc caches a sidebar item's favicon as
/// md5(item id). Not for security. CryptoKit's `Insecure.MD5` is Apple-only.
public enum MD5 {
    /// The digest as 32 lowercase hex digits.
    public static func hex(_ data: Data) -> String {
        digest(data).map { String(format: "%02x", $0) }.joined()
    }

    public static func digest(_ data: Data) -> [UInt8] {
        let shifts: [UInt32] = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                                5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
                                4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                                6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]
        let k: [UInt32] = (0..<64).map { (i: Int) -> UInt32 in UInt32(truncatingIfNeeded: Int64(abs(sin(Double(i + 1))) * 4_294_967_296)) }
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for i in 0..<8 { message.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i)))) }

        var a0: UInt32 = 0x6745_2301, b0: UInt32 = 0xEFCD_AB89, c0: UInt32 = 0x98BA_DCFE, d0: UInt32 = 0x1032_5476
        var words = [UInt32](repeating: 0, count: 16)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for j in 0..<16 {
                let o = chunk + j * 4
                words[j] = UInt32(message[o]) | UInt32(message[o + 1]) << 8 | UInt32(message[o + 2]) << 16 | UInt32(message[o + 3]) << 24
            }
            var a = a0, b = b0, c = c0, d = d0
            for i in 0..<64 {
                var f: UInt32
                let g: Int
                switch i {
                case 0..<16: f = (b & c) | (~b & d); g = i
                case 16..<32: f = (d & b) | (~d & c); g = (5 * i + 1) % 16
                case 32..<48: f = b ^ c ^ d; g = (3 * i + 5) % 16
                default: f = c ^ (b | ~d); g = (7 * i) % 16
                }
                f = f &+ a &+ k[i] &+ words[g]
                a = d
                d = c
                c = b
                b = b &+ (f << shifts[i] | f >> (32 - shifts[i]))
            }
            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }
        return [a0, b0, c0, d0].flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * UInt32($0))) } }
    }
}
