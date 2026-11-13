import CoreGraphics
import Foundation
import Testing
@testable import Terrazzo

@MainActor
struct VirtualWorkspacesTests {
    private func synced(_ displays: [String]) -> VirtualWorkspaces {
        var map = VirtualWorkspaces()
        map.sync(displays: displays)
        return map
    }

    @Test func eachDisplayStartsOnItsOwnWorkspace() {
        let map = synced(["A", "B"])
        #expect(map.number(on: "A") == 1)
        #expect(map.number(on: "B") == 2)
    }

    @Test func showingAnEmptyWorkspaceUsesTheFocusedDisplay() {
        var map = synced(["A", "B"])
        let display = map.show(5, focusedDisplay: "B", isEmpty: true)
        #expect(display == "B")
        #expect(map.number(on: "B") == 5)
        #expect(map.number(on: "A") == 1)
    }

    @Test func aWorkspaceWithWindowsReturnsToItsDisplay() {
        var map = synced(["A", "B"])
        _ = map.show(5, focusedDisplay: "A", isEmpty: true)
        _ = map.show(1, focusedDisplay: "A", isEmpty: true)
        let display = map.show(5, focusedDisplay: "B", isEmpty: false)
        #expect(display == "A")
        #expect(map.number(on: "A") == 5)
        #expect(map.number(on: "B") == 2)
    }

    @Test func aWorkspaceAlreadyShowingOnlyMovesAttentionThere() {
        var map = synced(["A", "B"])
        let display = map.show(2, focusedDisplay: "A", isEmpty: true)
        #expect(display == "B")
        #expect(map.number(on: "A") == 1)
    }

    @Test func aWorkspaceWhoseDisplayIsGoneComesToTheFocusedOne() {
        var map = synced(["A", "B"])
        _ = map.show(5, focusedDisplay: "B", isEmpty: true)
        map.sync(displays: ["A"])
        let display = map.show(5, focusedDisplay: "A", isEmpty: false)
        #expect(display == "A")
    }

    @Test func aReconnectedDisplayGetsAFreeWorkspace() {
        var map = synced(["A", "B"])
        _ = map.show(2, focusedDisplay: "A", isEmpty: false)
        map.sync(displays: ["A"])
        map.sync(displays: ["A", "B"])
        #expect(map.number(on: "A") != map.number(on: "B"))
    }

    @Test func hiddenWindowsParkInTheBottomRightCorner() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let origin = VirtualWorkspaces.hiddenOrigin(
            display: display, others: [], windowSize: CGSize(width: 500, height: 400))
        #expect(origin == CGPoint(x: 999, y: 799))
    }

    @Test func hiddenWindowsAvoidShowingOnANeighboringDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 1400)
        let origin = VirtualWorkspaces.hiddenOrigin(
            display: display, others: [right], windowSize: CGSize(width: 500, height: 400))
        #expect(origin == CGPoint(x: -499, y: 799))
    }

    // MARK: Going to an empty workspace

    @Test func anEmptyWorkspaceStaysCurrentWhileMacOSKeepsReportingTheOldWindow() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.focusObserved(window: 5, isShown: false)
        #expect(empty.display == "B")
        empty.focusObserved(window: 5, isShown: true)
        #expect(empty.display == "B")
    }

    @Test func movingToAnotherShownWindowEndsIt() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.focusObserved(window: 6, isShown: true)
        #expect(empty.display == nil)
    }

    @Test func aParkedWindowDoesNotEndIt() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.focusObserved(window: 6, isShown: false)
        #expect(empty.display == "B")
    }

    @Test func comingBackToTheSameWindowAfterLosingFocusEndsIt() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.focusObserved(window: nil, isShown: false)
        #expect(empty.display == "B")
        empty.focusObserved(window: 5, isShown: true)
        #expect(empty.display == nil)
    }

    @Test func theWindowLeftBehindDoesNotPullBackAfterFocusWasLost() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.focusObserved(window: nil, isShown: false)
        #expect(!empty.followsFocus(to: 5))
        #expect(empty.followsFocus(to: 6))
    }

    @Test func theWindowLeftBehindIsKeptAcrossAnotherEmptyWorkspace() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.focusObserved(window: nil, isShown: false)
        empty.wentToEmpty(display: "B", focused: nil)
        #expect(!empty.followsFocus(to: 5))
    }

    @Test func focusIsFollowedAgainOnceAWindowIsChosen() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.windowChosen()
        #expect(empty.followsFocus(to: 5))
    }

    @Test func focusIsFollowedWhenNotOnAnEmptyWorkspace() {
        #expect(EmptyWorkspaceFocus().followsFocus(to: 5))
    }

    @Test func choosingAWindowEndsIt() {
        var empty = EmptyWorkspaceFocus()
        empty.wentToEmpty(display: "B", focused: 5)
        empty.windowChosen()
        #expect(empty.display == nil)
    }

    // MARK: Pinned workspaces

    private func pinned() -> VirtualWorkspaces {
        var map = VirtualWorkspaces()
        map.setPins([1: "LG", 2: "LG", 3: "LG", 7: "SAM", 8: "SAM"])
        map.sync(displays: ["LG", "SAM"])
        return map
    }

    @Test func displaysStartOnTheirLowestPinnedWorkspace() {
        let map = pinned()
        #expect(map.number(on: "LG") == 1)
        #expect(map.number(on: "SAM") == 7)
    }

    @Test func aPinnedWorkspaceShowsOnItsDisplayEvenWhenEmpty() {
        var map = pinned()
        let display = map.show(8, focusedDisplay: "LG", isEmpty: true)
        #expect(display == "SAM")
        #expect(map.number(on: "SAM") == 8)
        #expect(map.number(on: "LG") == 1)
    }

    @Test func pinnedDisplayIsReportedForMovesToEmptyWorkspaces() {
        #expect(pinned().pinnedDisplay(of: 3) == "LG")
        #expect(pinned().pinnedDisplay(of: 7) == "SAM")
        #expect(pinned().pinnedDisplay(of: 5) == nil)
    }

    @Test func aPinToADisconnectedDisplayIsIgnored() {
        var map = pinned()
        map.sync(displays: ["LG"])
        #expect(map.pinnedDisplay(of: 7) == nil)
        #expect(map.show(7, focusedDisplay: "LG", isEmpty: true) == "LG")
    }

    @Test func reconnectingBringsAPinnedWorkspaceHome() {
        var map = pinned()
        map.sync(displays: ["LG"])
        _ = map.show(7, focusedDisplay: "LG", isEmpty: false)
        map.sync(displays: ["LG", "SAM"])
        #expect(map.number(on: "SAM") == 7)
        #expect(map.number(on: "LG") != 7)
    }

    @Test func aNewPinMovesAWorkspaceShowingOnTheWrongDisplay() {
        var map = synced(["LG", "SAM"])
        #expect(map.number(on: "SAM") == 2)
        map.setPins([2: "LG", 7: "SAM"])
        map.sync(displays: ["LG", "SAM"])
        #expect(map.number(on: "SAM") == 7)
    }

    @Test func aDisplayWithoutPinsAvoidsWorkspacesPinnedElsewhere() {
        var map = VirtualWorkspaces()
        map.setPins([1: "LG", 2: "LG"])
        map.sync(displays: ["LG", "OTHER"])
        #expect(map.number(on: "OTHER") == 3)
    }

    @Test func namesPickTheFirstMatchingDisplayIgnoringCase() {
        let displays = [display("a", "LG ULTRAWIDE"), display("b", "Odyssey G5")]
        let pins = VirtualWorkspaces.resolvePins(["1": "lg", "7": "odyssey", "8": "Dell", "x": "LG", "12": "LG"], displays: displays)
        #expect(pins == [1: "a", 7: "b"])
    }

    // MARK: Display candidates

    private func display(_ uuid: String, _ name: String, x: CGFloat = 0, builtIn: Bool = false) -> DisplayInfo {
        let frame = CGRect(x: x, y: 0, width: 1920, height: 1080)
        return DisplayInfo(uuid: uuid, name: name, frame: frame, visibleFrame: frame, isBuiltIn: builtIn)
    }

    private var mac: DisplayInfo { display("mac", "Built-in Retina Display", builtIn: true) }

    private let fallbacks: [String: DisplayPreference] = [
        "1": "@builtin", "4": ["Odyssey G5", "@external"], "7": ["LG ULTRAWIDE", "@external"],
    ]

    @Test func theFirstCandidateWinsWhileItsDisplayIsConnected() {
        let displays = [mac, display("ody", "Odyssey G5", x: 1512), display("lg", "LG ULTRAWIDE", x: 3432)]
        #expect(VirtualWorkspaces.resolvePins(fallbacks, displays: displays) == [1: "mac", 4: "ody", 7: "lg"])
    }

    @Test func anAbsentDisplayFallsBackToTheOnlyExternalOne() {
        let displays = [mac, display("dell", "DELL S2721DS", x: 1512)]
        #expect(VirtualWorkspaces.resolvePins(fallbacks, displays: displays) == [1: "mac", 4: "dell", 7: "dell"])
    }

    @Test func withNoExternalDisplayTheWorkspaceIsLeftUnpinned() {
        #expect(VirtualWorkspaces.resolvePins(fallbacks, displays: [mac]) == [1: "mac"])
    }

    @Test func theBuiltInDisplayMatchesWhateverLanguageNamesIt() {
        let displays = [display("dell", "DELL S2721DS", x: -1920), display("mac", "Pantalla Retina integrada", builtIn: true)]
        #expect(VirtualWorkspaces.resolvePins(["1": "@builtin"], displays: displays) == [1: "mac"])
    }

    @Test func anyExternalDisplayAvoidsOneThatAWorkspaceNames() {
        let displays = [display("lg", "LG ULTRAWIDE", x: -1920), mac, display("dell", "DELL S2721DS", x: 1512)]
        let pins = VirtualWorkspaces.resolvePins(["5": ["Odyssey G5", "@external"], "7": "LG"], displays: displays)
        #expect(pins == [5: "dell", 7: "lg"])
    }

    @Test func anyExternalDisplayIsOtherwiseTheLeftmostOne() {
        let displays = [mac, display("right", "DELL S2721DS", x: 1512), display("left", "LG ULTRAWIDE", x: -1920)]
        #expect(VirtualWorkspaces.resolvePins(["5": "@external"], displays: displays) == [5: "left"])
        let bothNamed = VirtualWorkspaces.resolvePins(["5": "@external", "6": "DELL", "7": "LG"], displays: displays)
        #expect(bothNamed == [5: "left", 6: "right", 7: "left"])
    }

    @Test func aDisplaySettingReadsAsOneNameOrAListOfCandidates() throws {
        let json = Data(#"{"1":"@builtin","4":["Odyssey G5","@external"]}"#.utf8)
        let decoded = try JSONDecoder().decode([String: DisplayPreference].self, from: json)
        #expect(decoded["1"]?.candidates == ["@builtin"])
        #expect(decoded["4"]?.candidates == ["Odyssey G5", "@external"])
    }

    @Test func oneCandidateIsSavedAsAStringAndSeveralAsAList() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved: [String: DisplayPreference] = ["1": "LG", "4": ["Odyssey G5", "@external"]]
        let text = String(decoding: try encoder.encode(saved), as: UTF8.self)
        #expect(text == #"{"1":"LG","4":["Odyssey G5","@external"]}"#)
    }

    @Test func aDisplayReturnsToTheWorkspaceItLeft() {
        var map = synced(["A"])
        map.sync(displays: [])
        map.sync(displays: ["A"])
        #expect(map.number(on: "A") == 1)
    }

    @Test func reconnectingOverAndOverKeepsTheSameWorkspace() {
        var map = synced(["A", "B"])
        for _ in 0..<12 {
            map.sync(displays: ["A"])
            map.sync(displays: ["A", "B"])
        }
        #expect(map.number(on: "B") == 2)
    }

    @Test func aReconnectingDisplayLeavesAWorkspaceWithWindowsElsewhereAlone() {
        var map = synced(["A", "B"])
        map.sync(displays: ["A"])
        _ = map.show(2, focusedDisplay: "A", isEmpty: true)
        _ = map.show(1, focusedDisplay: "A", isEmpty: true)
        map.sync(displays: ["A", "B"], occupied: [2: "A"])
        #expect(map.number(on: "B") != 2)
        #expect(map.number(on: "B") != 1)
        #expect(map.show(2, focusedDisplay: "A", isEmpty: false) == "A")
        #expect(map.number(on: "A") == 2)
    }

    /// Windows that moved to another display while theirs was away must still be found by number.
    @Test func aWorkspaceBelongsToTheDisplayHoldingItsWindows() {
        var map = synced(["A", "B"])
        map.adopt(7, on: "B")
        map.sync(displays: ["A", "B"], occupied: [7: "A"])
        #expect(map.home(of: 7) == "A")
        #expect(map.show(7, focusedDisplay: "B", isEmpty: false) == "A")
    }

    /// Showing a number on one display while its windows are on another would leave them out of reach.
    @Test func aDisplayStopsShowingAWorkspaceWhoseWindowsAreElsewhere() {
        var map = synced(["A", "B"])
        _ = map.show(7, focusedDisplay: "B", isEmpty: true)
        map.sync(displays: ["A", "B"], occupied: [7: "A"])
        #expect(map.number(on: "B") != 7)
        #expect(map.show(7, focusedDisplay: "B", isEmpty: false) == "A")
        #expect(map.number(on: "A") == 7)
    }

    @Test func aPinnedWorkspaceStaysOnItsDisplayWhateverHoldsItsWindows() {
        var map = synced(["A", "B"])
        map.setPins([7: "B"])
        map.sync(displays: ["A", "B"])
        _ = map.show(7, focusedDisplay: "A", isEmpty: true)
        map.sync(displays: ["A", "B"], occupied: [7: "A"])
        #expect(map.number(on: "B") == 7)
    }

    @Test func aNewDisplayDoesNotTakeAWorkspaceInUseAfterVisitingAllNine() {
        var map = synced(["A"])
        for number in VirtualWorkspaces.numbers { _ = map.show(number, focusedDisplay: "A", isEmpty: true) }
        _ = map.show(1, focusedDisplay: "A", isEmpty: true)
        map.sync(displays: ["A", "B"], occupied: [1: "A", 2: "A"])
        let number = map.number(on: "B")
        #expect(number != 1 && number != 2)
        #expect(map.show(2, focusedDisplay: "B", isEmpty: false) == "A")
    }

    @Test func aDisplayReturnsToItsOwnWorkspaceWithWindows() {
        var map = synced(["A", "B"])
        map.sync(displays: ["A"], occupied: [2: "B"])
        map.sync(displays: ["A", "B"], occupied: [2: "B"])
        #expect(map.number(on: "B") == 2)
    }

    @Test func aPinStillWinsOverWindowsOnAnotherDisplay() {
        var map = VirtualWorkspaces()
        map.setPins([7: "SAM"])
        map.sync(displays: ["LG", "SAM"], occupied: [7: "LG"])
        #expect(map.number(on: "SAM") == 7)
    }

    @Test func aPinnedWorkspaceSavedBySettingsLoads() throws {
        var settings = AppSettings()
        settings.workspaceDisplays = ["1": "LG"]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).workspaceDisplays == ["1": "LG"])
    }

    @Test func aSettingsFileKeepsNamesAsStringsAndFallbacksAsLists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data(#"{"workspaceDisplays": {"1": "LG", "4": ["Odyssey G5", "@external"]}}"#.utf8).write(to: url)
        let file = ConfigFile(url: url, defaults: AppSettings())

        let settings = try file.load()
        #expect(settings.workspaceDisplays == ["1": "LG", "4": ["Odyssey G5", "@external"]])

        try file.save(settings)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let displays = saved?["workspaceDisplays"] as? [String: Any]
        #expect(displays?["1"] as? String == "LG")
        #expect(displays?["4"] as? [String] == ["Odyssey G5", "@external"])
    }

    // MARK: Windows

    @Test func mergingBringsAWorkspacesWindowsToItsDisplay() {
        let source = WorkspaceKey(display: "A", space: 1, virtual: 2)
        let target = WorkspaceKey(display: "B", space: 1, virtual: 2)
        var state = filled([1, 2], on: source)
        state.mergeWorkspace(from: source, into: target, context: context(showing: target))
        #expect(state.workspaces[source] == nil)
        #expect(state.workspaces[target]?.tiles.map(\.windows) == [[1], [2]])
        #expect(state.apps[1] == "app")
    }

    private let one = WorkspaceKey(display: "A", space: 1)
    private let three = WorkspaceKey(display: "A", space: 1, virtual: 3)

    private func context(showing key: WorkspaceKey) -> TilingContext {
        TilingContext(
            screens: [ScreenGeometry(key: key, area: CGRect(x: 0, y: 0, width: 1920, height: 1080))],
            policy: TilingPolicy(gap: 0), minimumSize: { _ in .zero })
    }

    private func filled(_ ids: [WindowID], on key: WorkspaceKey) -> TilingState {
        var state = TilingState()
        for count in 1...ids.count {
            state.reconcile(
                Snapshot(
                    windows: ids[0..<count].map { ObservedWindow(id: $0, app: "app", key: key, frame: .zero) },
                    minimized: [], focused: nil), context: context(showing: key))
        }
        return state
    }

    @Test func aWorkspaceNotShowingKeepsItsWindows() {
        var state = filled([1, 2], on: one)
        state.reconcile(Snapshot(windows: [], minimized: [], focused: nil), context: context(showing: three))
        #expect(state.workspaces[one]?.tiles.map(\.windows) == [[1], [2]])
    }

    @Test func aWindowClosedInAWorkspaceNotShowingIsForgotten() {
        var state = filled([1, 2], on: one)
        state.reconcile(
            Snapshot(windows: [], minimized: [], focused: nil, existing: [2]), context: context(showing: three))
        #expect(state.workspaces[one]?.tiles.map(\.windows) == [[2]])
    }

    @Test func sendingMovesTheWindowAndReflowsTheSource() {
        var state = filled([1, 2], on: one)
        let next = state.send(1, to: three, context: context(showing: one))
        #expect(next == 2)
        #expect(state.workspaces[one]?.tiles.map(\.windows) == [[2]])
        #expect(state.workspaces[three]?.tiles.map(\.windows) == [[1]])
        #expect(state.apps[1] == "app")
    }

    @Test func sendingToAFullWorkspaceStillLandsThereAndFitsWhenShown() {
        var state = filled([1, 2, 3, 4, 5], on: three)
        var source = filled([9], on: one)
        source.workspaces[three] = state.workspaces[three]
        source.apps.merge(state.apps) { first, _ in first }
        state = source
        _ = state.send(9, to: three, context: context(showing: one))
        state.reconcile(
            Snapshot(
                windows: [1, 2, 3, 4, 5, 9].map { ObservedWindow(id: $0, app: "app", key: three, frame: .zero) },
                minimized: [], focused: nil), context: context(showing: three))
        #expect(state.workspaces[three]?.tiles.count == 3)
        #expect(state.workspaces[three]?.tiles.flatMap(\.windows).contains(9) == true)
    }

    @Test func sendingToTheCurrentWorkspaceDoesNothing() {
        var state = filled([1, 2], on: one)
        let next = state.send(1, to: one, context: context(showing: one))
        #expect(next == nil)
        #expect(state.workspaces[one]?.tiles.map(\.windows) == [[1], [2]])
    }

    @Test func aSendFromAnEmptiedWorkspaceHasNothingToFocus() {
        var state = filled([1], on: one)
        let next = state.send(1, to: three, context: context(showing: one))
        #expect(next == nil)
    }

    @Test func aWindowSentToACleanWorkspaceJoinsIt() {
        var state = filled([1], on: one)
        state.toggleClean(on: three, active: nil)
        _ = state.send(1, to: three, context: context(showing: one))
        #expect(state.workspaces[three]?.cleanSet == [1])
    }

    // MARK: Shortcuts

    @Test func workspaceShortcutsDefaultToControlAndDigits() {
        var map = ShortcutMap()
        #expect(map.combo(for: .workspace1)?.symbols == "⌃1")
        #expect(map.combo(for: .workspace9)?.symbols == "⌃9")
        #expect(map.combo(for: .moveToWorkspace1)?.symbols == "⌃⇧1")
        #expect(map.combo(for: .moveToWorkspace9)?.symbols == "⌃⇧9")
        map.prefix = .controlShift
        #expect(map.combo(for: .workspace3)?.symbols == "⌃3")
    }

    @Test func workspaceActionsKnowTheirNumbers() {
        #expect(ShortcutAction.workspace7.workspaceNumber == 7)
        #expect(ShortcutAction.moveToWorkspace4.moveWorkspaceNumber == 4)
        #expect(ShortcutAction.retile.workspaceNumber == nil)
    }

    @Test func preferencesKeepTheirIdOnWorkspaceOne() {
        #expect(ScreensFile.id(one) == "A#1")
        #expect(ScreensFile.id(three) == "A#1#3")
    }

    @Test func preferencesSurviveANewSpaceIdAfterReconnect() {
        var file = ScreensFile()
        let saved = ScreenPreferences(kind: .columns, count: 2)
        file.set(saved, for: three)
        let renumbered = WorkspaceKey(display: "A", space: 110, virtual: 3)
        #expect(file.preferences(for: renumbered) == saved)
        #expect(file.preferences(for: WorkspaceKey(display: "B", space: 110, virtual: 3)) == nil)
        #expect(file.preferences(for: WorkspaceKey(display: "A", space: 110, virtual: 4)) == nil)
    }

    @Test func preferencesOfTheExactSpaceWinOverTheFallback() {
        var file = ScreensFile()
        let other = WorkspaceKey(display: "A", space: 2, virtual: 3)
        file.set(ScreenPreferences(kind: .columns, count: 2), for: three)
        file.set(ScreenPreferences(kind: .rows, count: 3), for: other)
        #expect(file.preferences(for: three) == ScreenPreferences(kind: .columns, count: 2))
        #expect(file.preferences(for: other) == ScreenPreferences(kind: .rows, count: 3))
    }

    @Test func fallbackIdDoesNotCollideWithSpaceIds() {
        #expect(ScreensFile.fallbackID(one) != ScreensFile.id(one))
        #expect(ScreensFile.fallbackID(three) == "A#workspace#3")
    }
}
