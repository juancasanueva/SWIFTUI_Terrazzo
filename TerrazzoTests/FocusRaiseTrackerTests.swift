import Testing
@testable import Terrazzo

@MainActor
struct FocusRaiseTrackerTests {
    /// The decision for each refresh, in order.
    private func decisions(_ refreshes: [(focused: WindowID?, othersRaised: Bool)]) -> [Bool] {
        var tracker = FocusRaiseTracker()
        return refreshes.map { tracker.shouldRaise(focused: $0.focused, othersRaised: $0.othersRaised) }
    }

    @Test func aWindowIsRaisedWhenItGainsFocus() {
        #expect(decisions([(1, false), (2, false)]) == [true, true])
    }

    @Test func refreshesWithTheSameFocusDoNotRaiseAgain() {
        #expect(decisions([(1, false), (1, false), (1, false)]) == [true, false, false])
    }

    @Test func raisingAnotherWindowPutsTheFocusedOneBackOnTop() {
        #expect(decisions([(1, false), (1, true), (1, false)]) == [true, true, false])
    }

    @Test func comingBackToAWindowCountsAsAFocusChange() {
        #expect(decisions([(1, false), (nil, false), (1, false)]) == [true, false, true])
    }

    @Test func nothingIsRaisedWithoutAFocusedWindow() {
        #expect(decisions([(nil, true)]) == [false])
    }
}
