import CoreGraphics
import Testing
@testable import tiling

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

    // MARK: Windows

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

    // MARK: Shortcuts

    @Test func workspaceShortcutsDefaultToOptionAndDigits() {
        var map = ShortcutMap()
        #expect(map.combo(for: .workspace1)?.symbols == "⌥1")
        #expect(map.combo(for: .workspace9)?.symbols == "⌥9")
        #expect(map.combo(for: .moveToWorkspace1)?.symbols == "⌥⇧1")
        #expect(map.combo(for: .moveToWorkspace9)?.symbols == "⌥⇧9")
        map.prefix = .controlShift
        #expect(map.combo(for: .workspace3)?.symbols == "⌥3")
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
}
