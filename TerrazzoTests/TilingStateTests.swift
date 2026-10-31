import CoreGraphics
import Testing
@testable import Terrazzo

@MainActor
struct TilingStateTests {
    let left = WorkspaceKey(display: "L", space: 1)
    let right = WorkspaceKey(display: "R", space: 1)
    let leftArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let rightArea = CGRect(x: 1920, y: 0, width: 1920, height: 1080)

    private func context(
        policy: TilingPolicy = TilingPolicy(gap: 0), oneScreen: Bool = true, minimums: [String: CGSize] = [:]
    ) -> TilingContext {
        var screens = [ScreenGeometry(key: left, area: leftArea)]
        if !oneScreen { screens.append(ScreenGeometry(key: right, area: rightArea)) }
        return TilingContext(screens: screens, policy: policy, minimumSize: { minimums[$0] ?? .zero })
    }

    private func snapshot(
        _ ids: [WindowID], on key: WorkspaceKey? = nil, app: String = "app", minimized: [WindowID] = [],
        focused: WindowID? = nil
    ) -> Snapshot {
        Snapshot(
            windows: ids.map { ObservedWindow(id: $0, app: app, key: key ?? left, frame: .zero) },
            minimized: minimized, focused: focused)
    }

    private func peek(_ state: TilingState, _ ctx: TilingContext) -> Plan {
        var copy = state
        return copy.plan(context: ctx)
    }

    private func tiles(_ state: TilingState, _ key: WorkspaceKey? = nil) -> [[WindowID]] {
        state.workspaces[key ?? left]?.tiles.map(\.windows) ?? []
    }

    private func filled(_ ids: [WindowID], context ctx: TilingContext? = nil) -> TilingState {
        var state = TilingState()
        let ctx = ctx ?? context()
        for count in 1...ids.count {
            _ = state.reconcile(snapshot(Array(ids[0..<count])), context: ctx)
        }
        return state
    }

    // MARK: Auto-tiling

    @Test func windowsTakePlacesInOpeningOrder() {
        #expect(tiles(filled([1, 2, 3])) == [[1], [2], [3]])
    }

    @Test func closingThePrimaryPromotesTheNextAndKeepsOrder() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([2, 3]), context: context())
        #expect(tiles(state) == [[2], [3]])
    }

    @Test func planReflowsIntoTheFreedSpace() {
        var state = filled([1, 2])
        _ = state.reconcile(snapshot([2]), context: context())
        let plan = state.plan(context: context())
        #expect(plan.placements == [Placement(id: 2, frame: leftArea)])
    }

    @Test func windowsOnInactiveSpacesSurviveAScanOfOtherSpaces() {
        var state = filled([1, 2])
        let otherSpace = WorkspaceKey(display: "L", space: 2)
        let ctx = TilingContext(
            screens: [ScreenGeometry(key: otherSpace, area: leftArea)], policy: TilingPolicy(gap: 0),
            minimumSize: { _ in .zero })
        _ = state.reconcile(snapshot([3], on: otherSpace), context: ctx)
        #expect(tiles(state) == [[1], [2]])
        #expect(tiles(state, otherSpace) == [[3]])
    }

    @Test func windowsDraggedToAnotherSpaceLeaveTheOldWorkspace() {
        var state = filled([1, 2])
        let otherSpace = WorkspaceKey(display: "L", space: 2)
        let ctx = TilingContext(
            screens: [ScreenGeometry(key: otherSpace, area: leftArea)], policy: TilingPolicy(gap: 0),
            minimumSize: { _ in .zero })
        _ = state.reconcile(snapshot([2], on: otherSpace), context: ctx)
        #expect(tiles(state) == [[1]])
        #expect(tiles(state, otherSpace) == [[2]])
    }

    @Test func aTabReplacesItsWindowWithoutMovingAnything() {
        var state = filled([1, 2])
        _ = state.plan(context: context())
        let slotFrame = state.plan(context: context()).placements[0].frame
        let snap = Snapshot(
            windows: [
                ObservedWindow(id: 9, app: "app", key: left, frame: slotFrame),
                ObservedWindow(id: 2, app: "app", key: left, frame: .zero),
            ], minimized: [], focused: 9)
        _ = state.reconcile(snap, context: context())
        #expect(tiles(state) == [[9], [2]])
    }

    // MARK: Stacks

    @Test func aFullScreenStacksTheNewWindowOnTheActiveTile() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 2), context: context())
        let notices = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        #expect(tiles(state) == [[1], [4, 2], [3]])
        #expect(notices.contains(.stacked))
    }

    @Test func floatPolicyCentersOnceThenRejoinsWhenATiledWindowCloses() {
        let ctx = context(policy: TilingPolicy(gap: 0, whenFull: .floatInMiddle))
        var state = filled([1, 2, 3], context: ctx)
        let notices = state.reconcile(snapshot([1, 2, 3, 4]), context: ctx)
        #expect(notices.contains(.spaceFull))
        #expect(tiles(state) == [[1], [2], [3]])
        let first = state.plan(context: ctx)
        let second = state.plan(context: ctx)
        #expect(first.centered == [4])
        #expect(second.centered.isEmpty)
        _ = state.reconcile(snapshot([2, 3, 4]), context: ctx)
        #expect(tiles(state) == [[2], [3], [4]])
    }

    @Test func closingTheShowingWindowBringsForwardTheMostRecentlyUsed() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4, 5]), context: context())
        #expect(tiles(state)[2] == [5, 4, 3])
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        #expect(tiles(state)[2] == [4, 3])
    }

    @Test func aWindowMinimizedFromAStackReturnsToTheTopOfTheSameTile() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        _ = state.reconcile(snapshot([1, 2, 4], minimized: [3]), context: context())
        #expect(tiles(state)[2] == [4])
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        #expect(tiles(state)[2] == [3, 4])
    }

    @Test func aWindowAloneInItsTileComesBackWithItsOwnTile() {
        var state = filled([1, 2])
        _ = state.reconcile(snapshot([2], minimized: [1]), context: context())
        #expect(tiles(state) == [[2]])
        _ = state.reconcile(snapshot([1, 2]), context: context())
        #expect(tiles(state) == [[2], [1]])
    }

    @Test func aMinimizedStackWindowFindsItsTileAfterTilesShift() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        _ = state.reconcile(snapshot([1, 2, 3], minimized: [4]), context: context())
        _ = state.reconcile(snapshot([2, 3], minimized: [4]), context: context())
        #expect(tiles(state) == [[2], [3]])
        _ = state.reconcile(snapshot([2, 3, 4]), context: context())
        #expect(tiles(state) == [[2], [4, 3]])
    }

    @Test func reducingTheCountMergesTheLastTileAndIncreasingSplitsItBack() {
        var state = filled([1, 2, 3])
        _ = state.setCount(2, on: left, context: context())
        #expect(tiles(state) == [[1], [2, 3]])
        _ = state.setCount(3, on: left, context: context())
        #expect(tiles(state) == [[1], [2], [3]])
    }

    @Test func swappingMovesOnlyShowingWindows() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        state.swap(4, with: 1, context: context())
        #expect(tiles(state) == [[4], [2], [1, 3]])
    }

    @Test func cyclingMovesThroughTheStack() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        let shown = state.cycleStack(of: 4, forward: true)
        #expect(shown == 3)
        #expect(tiles(state)[2] == [3, 4])
    }

    @Test func cyclingFollowsTheFixedOrderOfTheBar() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4, 5]), context: context())
        #expect(tiles(state)[2] == [5, 4, 3])
        var shown = state.cycleStack(of: 5, forward: true)
        #expect(shown == 4)
        shown = state.cycleStack(of: 4, forward: true)
        #expect(shown == 3)
        shown = state.cycleStack(of: 3, forward: true)
        #expect(shown == 5)
        shown = state.cycleStack(of: 5, forward: false)
        #expect(shown == 3)
    }

    @Test func cyclingKeepsMostRecentUseForWhatClosesNext() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4, 5]), context: context())
        _ = state.cycleStack(of: 5, forward: true)
        #expect(tiles(state)[2] == [4, 5, 3])
    }

    private func twoAppStack() -> TilingState {
        var state = TilingState()
        let ctx = context(policy: { var p = TilingPolicy(gap: 0); p.count = 2; return p }())
        func window(_ id: WindowID, _ app: String) -> ObservedWindow {
            ObservedWindow(id: id, app: app, key: left, frame: .zero)
        }
        state.reconcile(Snapshot(windows: [window(1, "b")], minimized: [], focused: 1), context: ctx)
        state.reconcile(Snapshot(windows: [window(1, "b"), window(2, "b")], minimized: [], focused: 1), context: ctx)
        state.reconcile(
            Snapshot(windows: [window(1, "b"), window(2, "b"), window(3, "a")], minimized: [], focused: 3), context: ctx)
        return state
    }

    @Test func aStackIsCoveredWhenTheAppOfAWaitingWindowBecomesActive() {
        let state = twoAppStack()
        #expect(state.workspaces[left]?.tiles.map(\.windows) == [[3, 1], [2]])
        #expect(state.showingWindowsCovered(byApp: "b", on: [left]) == [3])
    }

    @Test func aStackIsNotCoveredByAnAppWithoutAWaitingWindowThere() {
        #expect(twoAppStack().showingWindowsCovered(byApp: "c", on: [left]).isEmpty)
    }

    @Test func theShowingWindowsOwnAppDoesNotCoverIt() {
        #expect(twoAppStack().showingWindowsCovered(byApp: "a", on: [left]).isEmpty)
    }

    @Test func screensNotShowingAreLeftAlone() {
        #expect(twoAppStack().showingWindowsCovered(byApp: "b", on: []).isEmpty)
    }

    @Test func movingAChipLeavesTheOldTileShowingItsNextWindow() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        state.moveToTile(4, tile: 0, on: left, context: context())
        #expect(tiles(state) == [[4, 1], [2], [3]])
    }

    @Test func allStackMembersGetTheTileFrame() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        let plan = state.plan(context: context())
        #expect(plan.placements.first { $0.id == 3 }?.frame == plan.placements.first { $0.id == 4 }?.frame)
        #expect(plan.showing == [1, 2, 4])
    }

    // MARK: Rearranging

    @Test func arrowSwapsWithTheNeighborInThatDirection() {
        var state = filled([1, 2, 3])
        _ = state.moveOrSwap(1, direction: .right, context: context())
        #expect(tiles(state) == [[2], [1], [3]])
        _ = state.moveOrSwap(1, direction: .down, context: context())
        #expect(tiles(state) == [[2], [3], [1]])
    }

    @Test func noNeighborMovesToTheNextScreen() {
        let ctx = context(oneScreen: false)
        var state = filled([1, 2], context: ctx)
        _ = state.moveOrSwap(2, direction: .right, context: ctx)
        #expect(tiles(state) == [[1]])
        #expect(tiles(state, right) == [[2]])
    }

    @Test func noValidTargetDoesNothing() {
        var state = filled([1, 2])
        _ = state.moveOrSwap(1, direction: .left, context: context())
        #expect(tiles(state) == [[1], [2]])
    }

    @Test func aFullTargetScreenSwapsOrStacksByPolicy() {
        var ctx = context(oneScreen: false)
        var state = filled([1], context: ctx)
        _ = state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: left, frame: .zero)]
                    + [5, 6, 7].map { ObservedWindow(id: $0, app: "app", key: right, frame: .zero) },
                minimized: [], focused: nil), context: ctx)
        var swapped = state
        _ = swapped.moveOrSwap(1, direction: .right, context: ctx)
        #expect(tiles(swapped) == [[5]])
        #expect(tiles(swapped, right) == [[1], [6], [7]])

        ctx.policy.movingIntoFull = .stackOnTop
        _ = state.moveOrSwap(1, direction: .right, context: ctx)
        #expect(tiles(state).isEmpty)
        #expect(tiles(state, right) == [[1, 5], [6], [7]])
    }

    @Test func roomButNotEnoughForTheAppStaysAndNamesIt() {
        let ctx = context(oneScreen: false, minimums: ["big": CGSize(width: 1700, height: 100)])
        var state = TilingState()
        _ = state.reconcile(
            Snapshot(
                windows: [
                    ObservedWindow(id: 1, app: "big", key: left, frame: .zero),
                    ObservedWindow(id: 5, app: "app", key: right, frame: .zero),
                ], minimized: [], focused: nil), context: ctx)
        let notices = state.moveOrSwap(1, direction: .right, context: ctx)
        #expect(notices == [.doesNotFit(app: "big")])
        #expect(tiles(state) == [[1]])
    }

    @Test func makingPrimarySwapsWithTheFirstTile() {
        var state = filled([1, 2, 3])
        state.makePrimary(3, context: context())
        #expect(tiles(state) == [[3], [2], [1]])
    }

    @Test func plainDropOnAFullScreenGoesBack() {
        let ctx = context(oneScreen: false, )
        var state = filled([1], context: ctx)
        _ = state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: left, frame: .zero)]
                    + [5, 6, 7].map { ObservedWindow(id: $0, app: "app", key: right, frame: .zero) },
                minimized: [], focused: nil), context: ctx)
        let joined = state.join(1, to: right, context: ctx)
        #expect(!joined)
        #expect(tiles(state) == [[1]])
    }

    @Test func directionalFocusFindsTheNeighbor() {
        let state = filled([1, 2, 3])
        #expect(state.focusTarget(from: 1, direction: .right, context: context()) == 2)
        #expect(state.focusTarget(from: 2, direction: .down, context: context()) == 3)
        #expect(state.focusTarget(from: 3, direction: .left, context: context()) == 1)
        #expect(state.focusTarget(from: 1, direction: .left, context: context()) == nil)
    }

    @Test func directionalFocusDoesNotChangeTheLayout() {
        let state = filled([1, 2, 3])
        _ = state.focusTarget(from: 1, direction: .right, context: context())
        #expect(tiles(state) == [[1], [2], [3]])
    }

    @Test func directionalFocusLandsOnTheShowingWindowOfAStack() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 3), context: context())
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: context())
        #expect(state.focusTarget(from: 2, direction: .down, context: context()) == 4)
    }

    @Test func directionalFocusCrossesToTheNearestWindowOnTheNextScreen() {
        let ctx = context(oneScreen: false)
        var state = TilingState()
        _ = state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: left, frame: .zero)]
                    + [5, 6].map { ObservedWindow(id: $0, app: "app", key: right, frame: .zero) },
                minimized: [], focused: nil), context: ctx)
        #expect(state.focusTarget(from: 1, direction: .right, context: ctx) == 5)
        #expect(state.focusTarget(from: 5, direction: .left, context: ctx) == 1)
    }

    @Test func directionalFocusStaysPutInCleanSpace() {
        var state = filled([1, 2])
        state.toggleClean(on: left, active: 1)
        #expect(state.focusTarget(from: 1, direction: .right, context: context()) == nil)
    }

    @Test func activateNextWrapsAcrossTiles() {
        let state = filled([1, 2, 3])
        #expect(state.adjacentWindow(to: 3, forward: true) == 1)
        #expect(state.adjacentWindow(to: 1, forward: false) == 3)
    }

    // MARK: Minimum sizes

    @Test func anAppThatCannotFitJoinsAStackOnTheDefaultPolicy() {
        let ctx = context(minimums: ["big": CGSize(width: 1700, height: 100)])
        var state = TilingState()
        _ = state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: left, frame: .zero)], minimized: [], focused: 1),
            context: ctx)
        _ = state.reconcile(
            Snapshot(
                windows: [
                    ObservedWindow(id: 1, app: "app", key: left, frame: .zero),
                    ObservedWindow(id: 2, app: "big", key: left, frame: .zero),
                ], minimized: [], focused: nil), context: ctx)
        #expect(tiles(state) == [[2, 1]])
    }

    @Test func anAppThatCannotFitFloatsOnTheFloatPolicy() {
        let ctx = context(
            policy: TilingPolicy(gap: 0, whenFull: .floatInMiddle),
            minimums: ["big": CGSize(width: 1700, height: 100)])
        var state = TilingState()
        _ = state.reconcile(
            Snapshot(
                windows: [
                    ObservedWindow(id: 1, app: "app", key: left, frame: .zero),
                    ObservedWindow(id: 2, app: "big", key: left, frame: .zero),
                ], minimized: [], focused: nil), context: ctx)
        #expect(tiles(state) == [[1]])
        #expect(peek(state, ctx).centered == [2])
    }

    // MARK: Modes

    @Test func focusModeFillsTheScreenAndRestoresOnToggle() {
        var state = filled([1, 2])
        state.toggleZoom(1, context: context())
        #expect(peek(state, context()).placements.first { $0.id == 1 }?.frame == leftArea)
        state.toggleZoom(1, context: context())
        #expect(peek(state, context()).placements.first { $0.id == 1 }?.frame.width == 960)
    }

    @Test func clickingAnotherWindowEndsFocusMode() {
        var state = filled([1, 2])
        state.toggleZoom(1, context: context())
        _ = state.reconcile(snapshot([1, 2], focused: 2), context: context())
        #expect(state.workspaces[left]?.zoomed == nil)
    }

    @Test func floatingRemovesFromLayoutAndUnfloatingReturnsIt() {
        var state = filled([1, 2])
        state.toggleFloat(2, context: context())
        #expect(tiles(state) == [[1]])
        _ = state.reconcile(snapshot([1, 2]), context: context())
        #expect(tiles(state) == [[1]])
        state.toggleFloat(2, context: context())
        _ = state.reconcile(snapshot([1, 2]), context: context())
        #expect(tiles(state) == [[1], [2]])
    }

    @Test func cleanSpaceMovesOnlyItsWindowsAndAdmitsBroughtWindows() {
        var state = filled([1, 2, 3])
        state.toggleClean(on: left, active: 1)
        var plan = state.plan(context: context())
        #expect(plan.placements == [Placement(id: 1, frame: leftArea)])
        _ = state.reconcile(snapshot([1, 2, 3], focused: 2), context: context())
        plan = state.plan(context: context())
        #expect(plan.placements.map(\.id) == [1, 2])
        state.toggleClean(on: left, active: nil)
        #expect(peek(state, context()).placements.count == 3)
    }

    @Test func emptyCleanSpaceAdoptsTheNextWindow() {
        var state = TilingState()
        state.toggleClean(on: left, active: nil)
        _ = state.reconcile(snapshot([1]), context: context())
        #expect(state.workspaces[left]?.cleanSet == [1])
    }

    // MARK: Spaces and limits

    private var otherSpace: WorkspaceKey { WorkspaceKey(display: "L", space: 2) }

    private func otherSpaceContext(policy: TilingPolicy = TilingPolicy(gap: 0)) -> TilingContext {
        TilingContext(
            screens: [ScreenGeometry(key: otherSpace, area: leftArea)], policy: policy, minimumSize: { _ in .zero })
    }

    @Test func aWindowLeavingAnInactiveSpaceDoesNotCollapseTheRest() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([3], on: otherSpace), context: otherSpaceContext())
        #expect(tiles(state) == [[1], [2]])
    }

    @Test func joiningAnotherSpaceDoesNotCollapseTheOldOne() {
        var state = filled([1, 2, 3])
        _ = state.reconcile(snapshot([9], on: otherSpace), context: otherSpaceContext())
        let joined = state.join(3, to: otherSpace, context: otherSpaceContext())
        #expect(joined)
        #expect(tiles(state) == [[1], [2]])
    }

    @Test func floatsSurviveASpaceSwitch() {
        var state = filled([1, 2])
        state.toggleFloat(2, context: context())
        var away = snapshot([], on: otherSpace)
        away.existing = [1, 2]
        _ = state.reconcile(away, context: otherSpaceContext())
        _ = state.reconcile(snapshot([1, 2]), context: context())
        #expect(tiles(state) == [[1]])
    }

    @Test func floatsAreForgottenOnceTheWindowIsGone() {
        var state = filled([1, 2])
        state.toggleFloat(2, context: context())
        var gone = snapshot([1])
        gone.existing = [1]
        _ = state.reconcile(gone, context: context())
        #expect(state.userFloats.isEmpty)
    }

    @Test func aLowerCountSetElsewhereAppliesOnReturn() {
        var state = filled([1, 2, 3])
        var ctx = context()
        ctx.policy.count = 2
        _ = state.reconcile(snapshot([1, 2, 3]), context: ctx)
        #expect(tiles(state) == [[1], [2, 3]])
    }

    @Test func aHigherLimitSplitsWaitingWindowsOnTheNextScan() {
        var ctx = context()
        ctx.policy.count = 2
        var state = filled([1, 2, 3], context: ctx)
        #expect(tiles(state).count == 2)
        ctx.policy.count = 3
        _ = state.reconcile(snapshot([1, 2, 3]), context: ctx)
        #expect(tiles(state).count == 3)
    }

    // MARK: Focus and Clean Space across windows

    @Test func focusOnAnUntrackedWindowEndsFocusMode() {
        var state = filled([1, 2])
        state.toggleZoom(1, context: context())
        var snap = snapshot([1, 2], focused: 77)
        snap.focusedApp = "calculator"
        _ = state.reconcile(snap, context: context())
        #expect(state.workspaces[left]?.zoomed == nil)
    }

    @Test func aFloatedWindowOfTheZoomedAppEndsFocusMode() {
        var state = filled([1, 2, 3])
        state.toggleFloat(3, context: context())
        state.toggleZoom(1, context: context())
        var snap = snapshot([1, 2, 3], focused: 3)
        snap.focusedApp = "app"
        _ = state.reconcile(snap, context: context())
        #expect(state.workspaces[left]?.zoomed == nil)
    }

    @Test func aDialogOfTheZoomedAppKeepsFocusMode() {
        var state = filled([1, 2])
        state.toggleZoom(1, context: context())
        var snap = snapshot([1, 2], focused: 77)
        snap.focusedApp = "app"
        _ = state.reconcile(snap, context: context())
        #expect(state.workspaces[left]?.zoomed == 1)
    }

    @Test func aCrossScreenSwapKeepsEachWindowInOnePlace() {
        let ctx = context(oneScreen: false)
        var state = TilingState()
        _ = state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: left, frame: .zero),
                    ObservedWindow(id: 2, app: "app", key: right, frame: .zero)],
                minimized: [], focused: nil), context: ctx)
        state.toggleClean(on: left, active: 1)
        state.swap(1, with: 2, context: ctx)
        let plan = peek(state, ctx)
        #expect(Set(plan.placements.map(\.id)).count == plan.placements.count)
        #expect(state.workspaces[left]?.cleanSet == [2])
    }

    @Test func aCrossScreenSwapEndsFocusModeOfTheMovedWindow() {
        let ctx = context(oneScreen: false)
        var state = TilingState()
        _ = state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: left, frame: .zero),
                    ObservedWindow(id: 2, app: "app", key: right, frame: .zero)],
                minimized: [], focused: nil), context: ctx)
        state.toggleZoom(1, context: ctx)
        state.swap(1, with: 2, context: ctx)
        #expect(state.workspaces[left]?.zoomed == nil)
    }

    @Test func focusModeIgnoresWindowsWithoutATile() {
        let ctx = context(policy: TilingPolicy(gap: 0, whenFull: .floatInMiddle))
        var state = filled([1, 2, 3], context: ctx)
        _ = state.reconcile(snapshot([1, 2, 3, 4]), context: ctx)
        state.toggleZoom(4, context: ctx)
        #expect(state.workspaces[left]?.zoomed == nil)
    }

    // MARK: Sizes

    @Test func sizesBelongToPositionsNotWindows() {
        var state = filled([1, 2])
        _ = state.dragEdges(of: 1, deltas: EdgeDeltas(maxX: 192), context: context())
        #expect(peek(state, context()).placements.first { $0.id == 1 }?.frame.width == 1152)
        state.swap(1, with: 2, context: context())
        #expect(peek(state, context()).placements.first { $0.id == 2 }?.frame.width == 1152)
        #expect(state.hasCustomSizes(on: left))
        state.resetSizes(on: left)
        #expect(peek(state, context()).placements.first { $0.id == 2 }?.frame.width == 960)
    }

    @Test func stepResizeAtTheLimitReportsIt() {
        var state = filled([1])
        let grown = state.step(1, grow: true, context: context())
        let shrunk = state.step(1, grow: false, context: context())
        #expect(grown == [.maximumSize])
        #expect(shrunk == [.minimumSize])
    }

    private func width(_ state: TilingState, _ id: WindowID) -> CGFloat? {
        peek(state, context()).placements.first { $0.id == id }?.frame.width
    }

    private func height(_ state: TilingState, _ id: WindowID) -> CGFloat? {
        peek(state, context()).placements.first { $0.id == id }?.frame.height
    }

    @Test func rightGrowsAWindowWithANeighborOnTheRight() {
        var state = filled([1, 2])
        let notices = state.nudge(1, direction: .right, context: context())
        #expect(notices.isEmpty)
        #expect(width(state, 1) == 1056)
        #expect(width(state, 2) == 864)
    }

    @Test func leftShrinksAWindowWithANeighborOnTheRightOnly() {
        var state = filled([1, 2])
        _ = state.nudge(1, direction: .left, context: context())
        #expect(width(state, 1) == 864)
        #expect(width(state, 2) == 1056)
    }

    @Test func rightShrinksTheRightmostWindowFromItsLeftEdge() {
        var state = filled([1, 2])
        _ = state.nudge(2, direction: .right, context: context())
        #expect(width(state, 2) == 864)
        #expect(width(state, 1) == 1056)
    }

    @Test func leftGrowsTheRightmostWindow() {
        var state = filled([1, 2])
        _ = state.nudge(2, direction: .left, context: context())
        #expect(width(state, 2) == 1056)
    }

    @Test func downMovesTheEdgeBetweenStackedCells() {
        var state = filled([1, 2, 3])
        _ = state.nudge(2, direction: .down, context: context())
        #expect(height(state, 2) == 594)
        #expect(height(state, 3) == 486)
        #expect(height(state, 1) == 1080)
    }

    @Test func upOnTheTopCellMovesItsLowerEdgeUp() {
        var state = filled([1, 2, 3])
        _ = state.nudge(2, direction: .up, context: context())
        #expect(height(state, 2) == 486)
    }

    @Test func aMiddleWindowMovesOnlyTheEdgeInThatDirection() {
        var ctx = context()
        ctx.policy.kind = .columns
        ctx.policy.kindIsChosen = true
        var state = filled([1, 2, 3], context: ctx)
        _ = state.nudge(2, direction: .right, context: ctx)
        let frames = peek(state, ctx).placements
        #expect(frames.first { $0.id == 1 }?.frame.width == 640)
        #expect(frames.first { $0.id == 2 }?.frame.width == 736)
        #expect(frames.first { $0.id == 3 }?.frame.width == 544)
    }

    @Test func theStepSizeComesFromThePolicy() {
        var ctx = context()
        ctx.policy.resizeStep = 0.025
        var state = filled([1, 2], context: ctx)
        _ = state.nudge(1, direction: .right, context: ctx)
        #expect(peek(state, ctx).placements.first { $0.id == 1 }?.frame.width == 1008)
    }

    @Test func biggerAndSmallerUseTheSameStep() {
        var ctx = context()
        ctx.policy.resizeStep = 0.025
        var state = filled([1, 2], context: ctx)
        _ = state.step(1, grow: true, context: ctx)
        #expect(peek(state, ctx).placements.first { $0.id == 1 }?.frame.width == 1008)
    }

    @Test func aWindowWithNoNeighborsReportsTheLimit() {
        var state = filled([1])
        #expect(state.nudge(1, direction: .right, context: context()) == [.maximumSize])
        #expect(state.nudge(1, direction: .up, context: context()) == [.maximumSize])
        #expect(!state.hasCustomSizes(on: left))
    }

    @Test func noRoomLeftReportsTheLimitInsteadOfMovingTheOtherEdge() {
        var ctx = context()
        ctx.policy.kind = .columns
        ctx.policy.kindIsChosen = true
        var state = filled([1, 2, 3], context: ctx)
        var notices: [Notice] = []
        for _ in 0..<40 { notices = state.nudge(2, direction: .right, context: ctx) }
        #expect(notices == [.maximumSize])
        #expect(peek(state, ctx).placements.first { $0.id == 1 }?.frame.width == 640)
    }

    @Test func shrinkingToTheFloorReportsTheMinimum() {
        var state = filled([1, 2])
        var notices: [Notice] = []
        for _ in 0..<40 { notices = state.nudge(1, direction: .left, context: context()) }
        #expect(notices == [.minimumSize])
    }

    @Test func nudgeDoesNothingInFocusModeOrCleanSpace() {
        var zoomed = filled([1, 2])
        zoomed.toggleZoom(1, context: context())
        #expect(zoomed.nudge(1, direction: .right, context: context()).isEmpty)
        #expect(!zoomed.hasCustomSizes(on: left))
        var clean = filled([1, 2])
        clean.toggleClean(on: left, active: 1)
        #expect(clean.nudge(1, direction: .right, context: context()).isEmpty)
        #expect(!clean.hasCustomSizes(on: left))
    }

    @Test func removedWindowLeavesNoFloatOrZoomResidue() {
        var state = filled([1, 2])
        state.toggleZoom(1, context: context())
        _ = state.reconcile(snapshot([2]), context: context())
        #expect(state.workspaces[left]?.zoomed == nil)
    }
}
