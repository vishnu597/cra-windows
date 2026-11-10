import CraCore
import Foundation
import Testing

struct JSONNumberTests {
    @Test func keepsBooleansSeparateFromZeroAndOne() throws {
        #expect(JSONNumber.isBoolean(NSNumber(value: true)))
        #expect(JSONNumber.isBoolean(NSNumber(value: false)))
        let numbers = [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: Int8(0)), NSNumber(value: Int8(1)),
                       NSNumber(value: UInt8(1)), NSNumber(value: 0.0), NSNumber(value: 1.0), NSNumber(value: Float(1))]
        #expect(numbers.allSatisfy { !JSONNumber.isBoolean($0) })
        let parsed = try #require(JSONSerialization.jsonObject(with: Data("[true,false,0,1,1.0,-1]".utf8)) as? [NSNumber])
        #expect(parsed.map(JSONNumber.isBoolean) == [true, true, false, false, false, false])
    }

    @Test func protocolBooleanAndNumberArgumentsStayStrict() {
        #expect(MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://example.test", "select": true]))
        for number in [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: Int8(1)), NSNumber(value: 1.0)] {
            #expect(!MCPProtocol.validate(name: "tab_open", arguments: ["url": "https://example.test", "select": number]))
        }
        #expect(!MCPProtocol.validate(name: "page_read", arguments: ["tabId": "t", "offset": true]))
        #expect(MCPProtocol.validate(name: "page_read", arguments: ["tabId": "t", "offset": NSNumber(value: Int8(1))]))
    }
}
