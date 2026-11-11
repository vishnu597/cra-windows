import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// JSON keeps booleans distinct from numbers even though Foundation bridges both to NSNumber.
public enum JSONNumber {
    public static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(CoreFoundation)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        // Swift's Windows Foundation does not expose the CoreFoundation module. Let its JSON
        // writer distinguish the underlying value; objCType alone also calls Int8 values "c".
        guard let data = try? JSONSerialization.data(withJSONObject: [number]) else { return false }
        return data == Data("[true]".utf8) || data == Data("[false]".utf8)
        #endif
    }
}
