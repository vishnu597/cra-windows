import CraCore
import Foundation
import Testing

/// Share links carry raw DEFLATE (FolderShareLink, SharedBoost). Off Apple platforms Foundation
/// has no codec, so Cra reads them with its own inflate: these pin that it reads what Apple's
/// and zlib's encoders write, and that what it writes reads back.
struct RawDeflateTests {
    private func bytes(_ base64: String) throws -> Data { try #require(Data(base64Encoded: base64)) }

    /// A Share Folder… link a Mac made (dynamic Huffman block).
    @Test func inflatesTheFolderLinkAMacMade() throws {
        let packed = "XY7NCoMwEIRfRfYcDBZiIVBaEMTeeuit9BB0awQ1wWxLQfLutQpBcpyfb5gZOpCPGQgklH3XanIJmaQwFketWhyBwXvJNJF1kvPX1knxqwbbI3eoplqfyZyKWwWebUuVIewjUv-9wIXqoGxYi4h9xC9CpPmRZYdU5Cu8-21ME99crIDWVoN_srV7bVC5oO5TZxfyAzLzPw"
        let base64 = packed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - packed.count % 4) % 4)
        let json = try #require(RawDeflate.inflate(try bytes(base64)))
        let text = try #require(String(data: json, encoding: .utf8))
        #expect(text.hasPrefix(#"{"i":[{"t":"Flights to Copenhagen","u":"https://flights.example/search?to=CPH"},"#))
        #expect(RawDeflate.decompress(try bytes(base64)) == json)
    }

    /// zlib's fixed Huffman block with long back-references, and a 9.9 KB dynamic one.
    @Test func inflatesWhatZlibWrites() throws {
        let fixed = "cy5KVMhOTS0oVijJSFVIy89JSS1SyMwD83Iy87L1FJxHVYyqGFUxqmJUBREqEjPyy5KzCitSc4qr0vNKkzILylOyiyrTcktGZdBlAA=="
        let letters: [String] = (0..<300).map { (i: Int) -> String in String(UnicodeScalar(UInt8(97 + (i * 7) % 26))) }
        let alphabet = letters.joined()
        let short = String(repeating: "Cra keeps the folder in the link. ", count: 40) + alphabet
        #expect(RawDeflate.inflate(try bytes(fixed)) == Data(short.utf8))

        let dynamic = "7ZVdbgJBDIOvwhF2+VnKcVqVB1QeUJf7q+w4tsMVKr+UKFMFh88zXh/323Pavf4879d5t96+r1+fv/vd43r9OVT7WJ+n0V34T+dqf+zWbciF/XlSNeNo3vMLDjo6jmHziSdLFRP6VoL2AZOO7J9YLDhoYtC/YI5Wm1lgtzcldXIqtdrQi+CkiUEfS3AHrnAe3aak5k81X8u9tLCq/d7E1NEyxpkRPolISshozGmQqhAlixGk8YM0RlUIkZWQEcQaUhWiJDGEtE0yI3wKkZWIEb6gQ2JlShJDSNs4M6J5gUhKyGhMaZCae4uSxQjSENwYybxAJCVkNEY1SHYvKEkMIW1zGiOZtxBZiRhBbYdk94KSxBDSNsyMaF4gkhIywpC3O233FiWLEaQh2IxoXiCSEjIag/qdlntBSWIEacxvjGTeQmQlYrTirfOdlntBSWIICc8dGdG8QGQlYsS3rt1pu7coWQwh4bkjI5oXiKSEjOqt852We4uSxQhSPXdiJPMWIilRCOCt852We0FJYggJzx0ZybyFyEocAvXWtTtt9yaRkkhJpCRSEimJlERKIiWRkkhJpCRSEimJlERKIiWRkkhJpCRSEimJlERKIiWRkkhJpCRSEimJlET6b4n0Bw=="
        let words: [String] = ["split", "pane", "boost", "folder", "little", "window", "peek", "library", "space", "profile", "sidebar", "archive"]
        let pieces: [String] = (0..<1200).map { (i: Int) -> String in words[(i * i + 3 * i) % words.count] + String(i % 17) }
        let long = pieces.joined(separator: " ")
        #expect(RawDeflate.inflate(try bytes(dynamic)) == Data(long.utf8))
    }

    @Test(arguments: [0, 1, 65_535, 65_536, 200_000])
    func storedBlocksReadBack(count: Int) throws {
        let data = Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let stored = RawDeflate.stored(data)
        #expect(stored.count == count + 5 * max(1, (count + 65_534) / 65_535))
        #expect(RawDeflate.inflate(stored) == data)
        let packed = try #require(RawDeflate.compress(data))
        #expect(RawDeflate.decompress(packed) == data)
    }

    @Test func refusesBrokenStreams() {
        #expect(RawDeflate.inflate(Data()) == nil)
        #expect(RawDeflate.inflate(Data([0x07])) == nil)  // BTYPE 11 is reserved
        #expect(RawDeflate.inflate(Data([0x01, 0x05, 0x00, 0x00, 0x00, 0x61])) == nil)  // LEN and NLEN disagree
        #expect(RawDeflate.inflate(Data([0x01, 0x05, 0x00, 0xFA, 0xFF, 0x61])) == nil)  // cut short
        #expect(RawDeflate.inflate(Data("not deflate at all".utf8)) == nil)
    }

    @Test func stopsAtTheLimit() throws {
        let data = Data(repeating: 0x41, count: 10_000)
        let packed = try #require(RawDeflate.compress(data))
        #expect(RawDeflate.decompress(packed, limit: 9_999) == nil)
        #expect(RawDeflate.decompress(packed, limit: 10_000) == data)
        #expect(RawDeflate.inflate(RawDeflate.stored(data), limit: 9_999) == nil)
    }
}
