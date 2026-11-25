import Testing
@testable import Terrazzo

struct WindowClassificationTests {
    @Test func aTiledWindowThatDoesNotAnswerStaysTiled() {
        #expect(WindowClassification.isTileable(read: nil, known: true))
    }

    @Test func aWindowNeverReadIsNotTiledUntilItAnswers() {
        #expect(!WindowClassification.isTileable(read: nil, known: nil))
    }

    @Test func aFreshAnswerReplacesWhatWasKnown() {
        #expect(!WindowClassification.isTileable(read: false, known: true))
        #expect(WindowClassification.isTileable(read: true, known: false))
    }

    @Test func passingEveryCheckMakesAStandardWindow() {
        #expect(WindowClassification.combine([{ true }, { true }]) == true)
    }

    @Test func anUnansweredCheckLeavesTheResultUnknown() {
        #expect(WindowClassification.combine([{ true }, { nil }, { true }]) == nil)
    }

    @Test func aFailedCheckRulesTheWindowOutWithoutAskingFurther() {
        var asked = 0
        let result = WindowClassification.combine([
            { asked += 1; return nil },
            { asked += 1; return false },
            { asked += 1; return true },
        ])
        #expect(result == false)
        #expect(asked == 2)
    }
}
