import CraCore
import Foundation
import Testing

/// Arc's command bar sizes (upstream 3bd548d), the Mac's and Windows' alike.
struct CommandBarLayoutTests {
    @Test func theBarGrowsByArcsRows() {
        #expect(CommandBarLayout.height(forRows: 0) == 64)
        #expect(CommandBarLayout.height(forRows: 1) == 64 + 46 + 18)
        // Five rows: 64 + 5 × 46 + 4 × 4 + 18.
        #expect(CommandBarLayout.height(forRows: 5) == 328)
        #expect(CommandBarLayout.width == 766)
    }
}
