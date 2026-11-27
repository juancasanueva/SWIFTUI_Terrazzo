import CoreGraphics
import Foundation
import Testing
@testable import Terrazzo

@MainActor
struct RefusalTrackerTests {
    private let area = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let start = Date(timeIntervalSince1970: 1000)

    private func frame(_ width: CGFloat, _ height: CGFloat = 700) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    @Test func aWindowThatAcceptsTheSizeIsFine() {
        var tracker = RefusalTracker()
        let verdict = tracker.note(
            id: 1, requested: frame(800), accepted: frame(800), previous: frame(1700), area: area, now: start)
        #expect(verdict == .none)
    }

    @Test func gridRoundingIsNotARefusal() {
        var tracker = RefusalTracker()
        let verdict = tracker.note(
            id: 1, requested: frame(800), accepted: frame(815), previous: frame(1700), area: area, now: start)
        #expect(verdict == .none)
    }

    @Test func clampingToAnotherSizeIsLearnedWhenItHappensTwice() {
        var tracker = RefusalTracker()
        let first = tracker.note(
            id: 1, requested: frame(600), accepted: frame(900), previous: frame(1700), area: area, now: start)
        #expect(first == .checkAgain(after: RefusalTracker.quickRetry))
        let second = tracker.note(
            id: 1, requested: frame(600), accepted: frame(900), previous: frame(900), area: area,
            now: start.addingTimeInterval(0.3))
        #expect(second == .learn(CGSize(width: 900, height: 0)))
    }

    @Test func aWindowThatStaysPutIsNotLearnedRightAway() {
        var tracker = RefusalTracker()
        let first = tracker.note(
            id: 1, requested: frame(1700), accepted: frame(3000), previous: frame(3000), area: area, now: start)
        #expect(first == .checkAgain(after: RefusalTracker.slowRetry))
        let second = tracker.note(
            id: 1, requested: frame(1700), accepted: frame(3000), previous: frame(3000), area: area,
            now: start.addingTimeInterval(0.3))
        #expect(second == .checkAgain(after: RefusalTracker.slowRetry))
    }

    @Test func aSlowAppThatCatchesUpIsNeverLearned() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(1700), accepted: frame(3000), previous: frame(3000), area: area, now: start)
        let caughtUp = tracker.note(
            id: 1, requested: frame(1700), accepted: frame(1700), previous: frame(3000), area: area,
            now: start.addingTimeInterval(1))
        #expect(caughtUp == .none)
        let later = tracker.note(
            id: 1, requested: frame(1700), accepted: frame(3000), previous: frame(3000), area: area,
            now: start.addingTimeInterval(1.2))
        #expect(later == .checkAgain(after: RefusalTracker.slowRetry))
    }

    @Test func aWindowAlreadyAtItsMinimumIsLearnedOnceItKeepsRefusing() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(800), accepted: frame(1200), previous: frame(1200), area: area, now: start)
        let verdict = tracker.note(
            id: 1, requested: frame(800), accepted: frame(1200), previous: frame(1200), area: area,
            now: start.addingTimeInterval(RefusalTracker.patience + 0.1))
        #expect(verdict == .learn(CGSize(width: 1200, height: 0)))
    }

    @Test func nearlyTheWholeScreenIsNeverAMinimum() {
        var tracker = RefusalTracker()
        var verdicts: [RefusalTracker.Verdict] = []
        for seconds in [0.0, 0.3, RefusalTracker.patience + 0.1] {
            verdicts.append(
                tracker.note(
                    id: 1, requested: frame(1700), accepted: frame(3410), previous: frame(1000), area: area,
                    now: start.addingTimeInterval(seconds)))
        }
        // A window not resized yet: looked at again, never learned, left alone once patience runs out.
        #expect(
            verdicts == [
                .checkAgain(after: RefusalTracker.quickRetry), .checkAgain(after: RefusalTracker.quickRetry), .none,
            ])
    }

    @Test func aWindowThatHasNotGrownYetIsCheckedAgain() {
        var tracker = RefusalTracker()
        let verdict = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area, now: start)
        #expect(verdict == .checkAgain(after: RefusalTracker.quickRetry))
    }

    @Test func aWindowThatNeverGrowsIsLeftAloneOncePatienceRunsOut() {
        var tracker = RefusalTracker()
        let first = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area, now: start)
        let second = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area,
            now: start.addingTimeInterval(1))
        let last = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area,
            now: start.addingTimeInterval(RefusalTracker.patience + 0.1))
        #expect(first == .checkAgain(after: RefusalTracker.quickRetry))
        #expect(second == .checkAgain(after: RefusalTracker.quickRetry))
        #expect(last == .none)
    }

    @Test func aWindowThatGrowsLateStartsAFreshWaitNextTime() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area, now: start)
        let grown = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(1694), previous: frame(888), area: area,
            now: start.addingTimeInterval(0.3))
        let later = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area,
            now: start.addingTimeInterval(RefusalTracker.patience + 1))
        #expect(grown == .none)
        #expect(later == .checkAgain(after: RefusalTracker.quickRetry))
    }

    @Test func aWindowSeenInPlaceStartsAFreshWaitNextTime() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area, now: start)
        // It grew without being asked again, so only its placement saw it in place.
        tracker.forget(1)
        let later = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area,
            now: start.addingTimeInterval(60))
        #expect(later == .checkAgain(after: RefusalTracker.quickRetry))
    }

    @Test func forgettingOneWindowKeepsAnotherWaiting() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area, now: start)
        _ = tracker.note(
            id: 2, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area, now: start)
        tracker.forget(1)
        let other = tracker.note(
            id: 2, requested: frame(1694), accepted: frame(888), previous: frame(888), area: area,
            now: start.addingTimeInterval(RefusalTracker.patience + 0.1))
        #expect(other == .none)
    }

    @Test func gridRoundingDownIsNotAWindowLeftBehind() {
        var tracker = RefusalTracker()
        let verdict = tracker.note(
            id: 1, requested: frame(800), accepted: frame(785), previous: frame(1700), area: area, now: start)
        #expect(verdict == .none)
    }

    @Test func aWindowThatHasNotGrownTallerYetIsCheckedAgain() {
        var tracker = RefusalTracker()
        let verdict = tracker.note(
            id: 1, requested: frame(800, 1360), accepted: frame(800, 673), previous: frame(800, 673), area: area,
            now: start)
        #expect(verdict == .checkAgain(after: RefusalTracker.quickRetry))
    }

    @Test func heightIsJudgedOnItsOwn() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(800, 300), accepted: frame(800, 500), previous: frame(800, 700), area: area,
            now: start)
        let verdict = tracker.note(
            id: 1, requested: frame(800, 300), accepted: frame(800, 500), previous: frame(800, 500), area: area,
            now: start.addingTimeInterval(0.3))
        #expect(verdict == .learn(CGSize(width: 0, height: 500)))
    }

    @Test func differentWindowsAreTrackedApart() {
        var tracker = RefusalTracker()
        _ = tracker.note(
            id: 1, requested: frame(600), accepted: frame(900), previous: frame(1700), area: area, now: start)
        let other = tracker.note(
            id: 2, requested: frame(600), accepted: frame(900), previous: frame(900), area: area,
            now: start.addingTimeInterval(0.1))
        #expect(other == .checkAgain(after: RefusalTracker.slowRetry))
    }
}
