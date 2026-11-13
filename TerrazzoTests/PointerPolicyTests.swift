import CoreGraphics
import Foundation
import Testing
@testable import Terrazzo

@MainActor
struct PointerPolicyTests {
    private let both = AppSettings.MovePointer()
    private let lg = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let samsung = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    private let window = CGRect(x: 1700, y: 50, width: 1700, height: 700)

    private func ownWindowTakesPointer(at pointer: CGPoint, ignoresMouse: Bool) -> Bool {
        PointerPolicy.ownWindowTakesPointer(frame: window, ignoresMouse: ignoresMouse, pointer: pointer)
    }

    @Test func settingsAndPanelsKeepThePointerFromTheWindowsBelow() {
        #expect(ownWindowTakesPointer(at: CGPoint(x: 2000, y: 300), ignoresMouse: false))
    }

    @Test func overlaysLetThePointerThrough() {
        #expect(!ownWindowTakesPointer(at: CGPoint(x: 2000, y: 300), ignoresMouse: true))
    }

    @Test func anOwnWindowTakesThePointerOnlyInsideItsBounds() {
        // Just outside its edge the pointer is over whatever is beside it, tolerance or not.
        #expect(!ownWindowTakesPointer(at: CGPoint(x: 1697, y: 300), ignoresMouse: false))
    }

    @Test func bothRulesAreOnByDefault() {
        #expect(both.onWindowFocus)
        #expect(both.onMonitorChange)
    }

    @Test func thePointerGoesToTheCenterOfAWindowItIsNotOver() {
        let target = PointerPolicy.destination(
            pointer: CGPoint(x: 100, y: 100), window: window, display: lg, rules: both)
        #expect(target == CGPoint(x: 2550, y: 400))
    }

    @Test func thePointerStaysWhenItIsAlreadyOverTheWindow() {
        let target = PointerPolicy.destination(
            pointer: CGPoint(x: 1800, y: 100), window: window, display: lg, rules: both)
        #expect(target == nil)
    }

    @Test func thePointerStaysOnTheBarAboveTheWindow() {
        let target = PointerPolicy.destination(
            pointer: CGPoint(x: 2550, y: 46), window: window, display: lg, rules: both)
        #expect(target == nil)
    }

    @Test func anEmptyWorkspaceSendsThePointerToItsMonitorsCenter() {
        let target = PointerPolicy.destination(
            pointer: CGPoint(x: 100, y: 100), window: nil, display: samsung, rules: both)
        #expect(target == CGPoint(x: -1280, y: 720))
    }

    @Test func thePointerStaysOnAnEmptyWorkspaceOfItsOwnMonitor() {
        let target = PointerPolicy.destination(
            pointer: CGPoint(x: 100, y: 100), window: nil, display: lg, rules: both)
        #expect(target == nil)
    }

    @Test func withOnlyTheMonitorRuleItStaysOnTheSameMonitor() {
        let rules = AppSettings.MovePointer(onWindowFocus: false, onMonitorChange: true)
        #expect(
            PointerPolicy.destination(pointer: CGPoint(x: 100, y: 100), window: window, display: lg, rules: rules) == nil)
    }

    @Test func withOnlyTheMonitorRuleItGoesToTheOtherMonitorsCenter() {
        let rules = AppSettings.MovePointer(onWindowFocus: false, onMonitorChange: true)
        let target = PointerPolicy.destination(
            pointer: CGPoint(x: 100, y: 100), window: CGRect(x: -2500, y: 50, width: 500, height: 500),
            display: samsung, rules: rules)
        #expect(target == CGPoint(x: -1280, y: 720))
    }

    @Test func withOnlyTheWindowRuleAnEmptyWorkspaceLeavesThePointer() {
        let rules = AppSettings.MovePointer(onWindowFocus: true, onMonitorChange: false)
        #expect(
            PointerPolicy.destination(pointer: CGPoint(x: 100, y: 100), window: nil, display: samsung, rules: rules)
                == nil)
    }

    @Test func withBothOffItNeverMoves() {
        let rules = AppSettings.MovePointer(onWindowFocus: false, onMonitorChange: false)
        #expect(
            PointerPolicy.destination(pointer: CGPoint(x: 100, y: 100), window: window, display: samsung, rules: rules)
                == nil)
    }

    @Test func settingsLoadFromAPartialFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(#"{"movePointer": {"onWindowFocus": false}}"#.utf8).write(to: url)
        let settings = try ConfigFile(url: url, defaults: AppSettings()).load()
        #expect(!settings.movePointer.onWindowFocus)
        #expect(settings.movePointer.onMonitorChange)
    }
}
