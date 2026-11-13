import Testing
@testable import Terrazzo

struct CleanSpaceOrderTests {
    @Test func theFocusedWindowIsRaisedLast() {
        #expect(CleanSpaceOrder.raising([1, 2, 3], focused: 1) == [2, 3, 1])
        #expect(CleanSpaceOrder.raising([1, 2, 3], focused: 2) == [1, 3, 2])
    }

    @Test func theOrderWindowsJoinedInHoldsWithoutAFocusedWindowAmongThem() {
        #expect(CleanSpaceOrder.raising([1, 2, 3], focused: nil) == [1, 2, 3])
        #expect(CleanSpaceOrder.raising([1, 2, 3], focused: 9) == [1, 2, 3])
        #expect(CleanSpaceOrder.raising([1, 2, 3], focused: 3) == [1, 2, 3])
    }

    @Test func anEmptySetRaisesNothing() {
        #expect(CleanSpaceOrder.raising([], focused: 1).isEmpty)
    }
}
