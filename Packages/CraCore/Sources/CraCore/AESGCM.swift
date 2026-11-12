import Foundation

/// AES-GCM (FIPS 197, NIST SP 800-38D) with a 96-bit nonce and a 128-bit tag: what Chromium on
/// Windows seals saved passwords and cookies with (os_crypt's "v10"). CryptoKit's `AES.GCM` is
/// Apple-only; this one runs wherever CraCore does, so the Windows import's crypto is tested on
/// Linux too. Byte by byte and not constant-time: it reads and writes the user's own data on
/// their own computer, a few thousand short values at a time.
public enum AESGCM {
    public static let nonceSize = 12
    public static let tagSize = 16

    /// The ciphertext and its tag; nil for a key that isn't 16, 24 or 32 bytes or a nonce that
    /// isn't 12.
    public static func seal(_ plaintext: Data, key: Data, nonce: Data, authenticating aad: Data = Data()) -> (ciphertext: Data, tag: Data)? {
        guard let aes = AESKey(key), nonce.count == nonceSize else { return nil }
        let j0 = [UInt8](nonce) + [0, 0, 0, 1]
        let ciphertext = ctr(aes, start: j0, [UInt8](plaintext))
        let tag = self.tag(aes, j0: j0, aad: [UInt8](aad), ciphertext: ciphertext)
        return (Data(ciphertext), Data(tag))
    }

    /// The plaintext; nil when the tag doesn't match (a wrong key or a changed value).
    public static func open(_ ciphertext: Data, key: Data, nonce: Data, tag: Data, authenticating aad: Data = Data()) -> Data? {
        guard let aes = AESKey(key), nonce.count == nonceSize, tag.count == tagSize else { return nil }
        let j0 = [UInt8](nonce) + [0, 0, 0, 1]
        let sealed = [UInt8](ciphertext)
        let expected = self.tag(aes, j0: j0, aad: [UInt8](aad), ciphertext: sealed)
        var difference: UInt8 = 0
        for (a, b) in zip(expected, [UInt8](tag)) { difference |= a ^ b }
        guard difference == 0 else { return nil }
        return Data(ctr(aes, start: j0, sealed))
    }

    // MARK: GCM

    /// CTR mode from inc32(J0).
    private static func ctr(_ aes: AESKey, start j0: [UInt8], _ input: [UInt8]) -> [UInt8] {
        var counter = j0
        var out = [UInt8](repeating: 0, count: input.count)
        var offset = 0
        while offset < input.count {
            increment(&counter)
            let stream = aes.encrypt(counter)
            for i in 0..<min(16, input.count - offset) { out[offset + i] = input[offset + i] ^ stream[i] }
            offset += 16
        }
        return out
    }

    private static func increment(_ block: inout [UInt8]) {
        var i = 15
        while i >= 12 {
            block[i] &+= 1
            if block[i] != 0 { return }
            i -= 1
        }
    }

    private static func tag(_ aes: AESKey, j0: [UInt8], aad: [UInt8], ciphertext: [UInt8]) -> [UInt8] {
        let h = Block(aes.encrypt([UInt8](repeating: 0, count: 16)))
        var y = Block(hi: 0, lo: 0)
        func absorb(_ bytes: [UInt8]) {
            var offset = 0
            while offset < bytes.count {
                var chunk = [UInt8](repeating: 0, count: 16)
                for i in 0..<min(16, bytes.count - offset) { chunk[i] = bytes[offset + i] }
                y = (y ^ Block(chunk)) * h
                offset += 16
            }
        }
        absorb(aad)
        absorb(ciphertext)
        y = (y ^ Block(hi: UInt64(aad.count) * 8, lo: UInt64(ciphertext.count) * 8)) * h
        let mask = aes.encrypt(j0)
        return zip(y.bytes, mask).map { $0 ^ $1 }
    }

    /// An element of GF(2^128) in GCM's bit order: the first byte's high bit is x^0.
    private struct Block {
        var hi: UInt64
        var lo: UInt64

        init(hi: UInt64, lo: UInt64) {
            self.hi = hi
            self.lo = lo
        }

        init(_ bytes: [UInt8]) {
            hi = 0
            lo = 0
            for i in 0..<8 { hi = hi << 8 | UInt64(bytes[i]) }
            for i in 8..<16 { lo = lo << 8 | UInt64(bytes[i]) }
        }

        var bytes: [UInt8] {
            (0..<8).map { UInt8(truncatingIfNeeded: hi >> UInt64(56 - 8 * $0)) }
                + (0..<8).map { UInt8(truncatingIfNeeded: lo >> UInt64(56 - 8 * $0)) }
        }

        static func ^ (a: Block, b: Block) -> Block { Block(hi: a.hi ^ b.hi, lo: a.lo ^ b.lo) }

        /// SP 800-38D algorithm 1.
        static func * (x: Block, y: Block) -> Block {
            var z = Block(hi: 0, lo: 0)
            var v = y
            for i in 0..<128 {
                let bit = i < 64 ? (x.hi >> UInt64(63 - i)) & 1 : (x.lo >> UInt64(127 - i)) & 1
                if bit == 1 { z = z ^ v }
                let carry = v.lo & 1
                v.lo = v.lo >> 1 | v.hi << 63
                v.hi = v.hi >> 1
                if carry == 1 { v.hi ^= 0xE100_0000_0000_0000 }
            }
            return z
        }
    }
}

/// AES's forward cipher with an expanded key (FIPS 197), all GCM needs.
struct AESKey {
    private let roundKeys: [UInt8]
    private let rounds: Int

    init?(_ key: Data) {
        let bytes = [UInt8](key)
        guard [16, 24, 32].contains(bytes.count) else { return nil }
        let nk = bytes.count / 4
        let total = nk + 6
        var w = bytes
        var rcon: UInt8 = 1
        for i in nk..<(4 * (total + 1)) {
            var temp = Array(w[(4 * (i - 1))..<(4 * i)])
            if i % nk == 0 {
                temp = [temp[1], temp[2], temp[3], temp[0]].map { Self.sbox[Int($0)] }
                temp[0] ^= rcon
                rcon = Self.xtime(rcon)
            } else if nk > 6 && i % nk == 4 {
                temp = temp.map { Self.sbox[Int($0)] }
            }
            for j in 0..<4 { w.append(w[4 * (i - nk) + j] ^ temp[j]) }
        }
        roundKeys = w
        rounds = total
    }

    func encrypt(_ block: [UInt8]) -> [UInt8] {
        var s = block
        for i in 0..<16 { s[i] ^= roundKeys[i] }
        for round in 1...rounds {
            // SubBytes and ShiftRows: row r moves r columns left (the state is column-major).
            var t = [UInt8](repeating: 0, count: 16)
            for c in 0..<4 {
                for r in 0..<4 { t[r + 4 * c] = Self.sbox[Int(s[r + 4 * ((c + r) % 4)])] }
            }
            if round < rounds {
                for c in 0..<4 {
                    let a0 = t[4 * c], a1 = t[4 * c + 1], a2 = t[4 * c + 2], a3 = t[4 * c + 3]
                    let all = a0 ^ a1 ^ a2 ^ a3
                    t[4 * c] = a0 ^ all ^ Self.xtime(a0 ^ a1)
                    t[4 * c + 1] = a1 ^ all ^ Self.xtime(a1 ^ a2)
                    t[4 * c + 2] = a2 ^ all ^ Self.xtime(a2 ^ a3)
                    t[4 * c + 3] = a3 ^ all ^ Self.xtime(a3 ^ a0)
                }
            }
            for i in 0..<16 { t[i] ^= roundKeys[16 * round + i] }
            s = t
        }
        return s
    }

    static func xtime(_ x: UInt8) -> UInt8 { (x << 1) ^ (x & 0x80 != 0 ? 0x1B : 0) }

    /// The S-box from its definition: the multiplicative inverse in GF(2^8), then the affine map.
    static let sbox: [UInt8] = {
        func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
            var a = a, b = b, p: UInt8 = 0
            while b != 0 {
                if b & 1 != 0 { p ^= a }
                a = xtime(a)
                b >>= 1
            }
            return p
        }
        return (0..<256).map { (n: Int) -> UInt8 in
            let x = UInt8(n)
            // x^254 is x's inverse (0 stays 0).
            var inverse: UInt8 = 1, power = x, e = 254
            while e > 0 {
                if e & 1 != 0 { inverse = multiply(inverse, power) }
                power = multiply(power, power)
                e >>= 1
            }
            if x == 0 { inverse = 0 }
            func rotl(_ v: UInt8, _ k: UInt8) -> UInt8 { (v << k) | (v >> (8 - k)) }
            return inverse ^ rotl(inverse, 1) ^ rotl(inverse, 2) ^ rotl(inverse, 3) ^ rotl(inverse, 4) ^ 0x63
        }
    }()
}
