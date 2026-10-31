import CoreGraphics
import Foundation
import Testing
@testable import Terrazzo

@MainActor
struct SavedLayoutTests {
    private let one = WorkspaceKey(display: "A", space: 1)
    private let three = WorkspaceKey(display: "A", space: 1, virtual: 3)

    private func context(_ key: WorkspaceKey? = nil) -> TilingContext {
        TilingContext(
            screens: [ScreenGeometry(key: key ?? one, area: CGRect(x: 0, y: 0, width: 1920, height: 1080))],
            policy: TilingPolicy(gap: 0), minimumSize: { _ in .zero })
    }

    private func arranged() -> TilingState {
        var state = TilingState()
        for count in 1...3 {
            state.reconcile(
                Snapshot(
                    windows: (1...count).map { ObservedWindow(id: WindowID($0), app: "app", key: one, frame: .zero) },
                    minimized: [], focused: nil), context: context())
        }
        state.swap(1, with: 3, context: context())
        return state
    }

    private let owners: [WindowID: String] = [1: "app", 2: "app", 3: "app", 4: "app", 5: "app"]

    private func reloaded(_ state: TilingState, owners: [WindowID: String]? = nil) throws -> TilingState {
        let data = try JSONEncoder().encode(state.savedLayout(map: VirtualWorkspaces()))
        let saved = try JSONDecoder().decode(SavedLayout.self, from: data)
        var fresh = TilingState()
        fresh.restore(saved, owners: owners ?? self.owners)
        return fresh
    }

    @Test func tilesComeBackInTheirPlaces() throws {
        let fresh = try reloaded(arranged())
        #expect(fresh.workspaces[one]?.tiles.map(\.windows) == [[3], [2], [1]])
    }

    @Test func aStackKeepsItsShowingWindowAndRecentOrder() throws {
        var state = arranged()
        state.moveToTile(2, tile: 0, on: one, context: context())
        state.show(3)
        #expect(state.workspaces[one]?.tiles.map(\.windows) == [[3, 2], [1]])
        let fresh = try reloaded(state)
        #expect(fresh.workspaces[one]?.tiles.map(\.windows) == [[3, 2], [1]])
    }

    @Test func windowsOnAWorkspaceNotShowingStayThere() throws {
        var state = arranged()
        _ = state.send(1, to: three, context: context())
        let fresh = try reloaded(state)
        #expect(fresh.workspaces[three]?.tiles.map(\.windows) == [[1]])
        #expect(fresh.key(of: 1) == three)
    }

    @Test func windowsThatNoLongerExistAreDropped() throws {
        let fresh = try reloaded(arranged(), owners: [1: "app", 3: "app"])
        #expect(fresh.workspaces[one]?.tiles.map(\.windows) == [[3], [1]])
    }

    @Test func aWindowNumberReusedByAnotherAppIsDropped() throws {
        let fresh = try reloaded(arranged(), owners: [1: "app", 2: "other", 3: "app"])
        #expect(fresh.workspaces[one]?.tiles.map(\.windows) == [[3], [1]])
        #expect(fresh.apps[2] == nil)
    }

    @Test func floatsAreRememberedWhileTheyExist() throws {
        var state = arranged()
        state.toggleFloat(2, context: context())
        #expect(try reloaded(state).userFloats == [2])
        #expect(try reloaded(state, owners: [1: "app", 3: "app"]).userFloats.isEmpty)
    }

    @Test func theFirstScanLeavesARestoredLayoutAlone() throws {
        var fresh = try reloaded(arranged())
        fresh.reconcile(
            Snapshot(
                windows: [1, 2, 3].map { ObservedWindow(id: $0, app: "app", key: one, frame: .zero) },
                minimized: [], focused: nil, existing: [1, 2, 3]), context: context())
        #expect(fresh.workspaces[one]?.tiles.map(\.windows) == [[3], [2], [1]])
    }

    @Test func aWindowOpenedWhileTheAppWasOffTakesAPlace() throws {
        var state = TilingState()
        state.reconcile(
            Snapshot(
                windows: [ObservedWindow(id: 1, app: "app", key: one, frame: .zero)], minimized: [], focused: nil),
            context: context())
        var fresh = try reloaded(state)
        fresh.reconcile(
            Snapshot(
                windows: [1, 5].map { ObservedWindow(id: $0, app: "app", key: one, frame: .zero) },
                minimized: [], focused: nil), context: context())
        #expect(fresh.workspaces[one]?.tiles.map(\.windows) == [[1], [5]])
    }

    @Test func emptyWorkspacesAreNotSaved() {
        var state = arranged()
        state.workspaces[three] = Workspace()
        #expect(state.savedLayout(map: VirtualWorkspaces()).entries.count == 1)
    }

    @Test func sessionModesAreNotRestored() throws {
        var state = arranged()
        state.toggleZoom(3, context: context())
        state.toggleClean(on: one, active: 3)
        let fresh = try reloaded(state)
        #expect(fresh.workspaces[one]?.zoomed == nil)
        #expect(fresh.workspaces[one]?.cleanSet == nil)
    }

    @Test func restoringKeepsLayoutPreferencesAlreadyLoaded() throws {
        var fresh = TilingState()
        fresh.workspaces[one] = Workspace(kind: .side, count: 2)
        let saved = arranged().savedLayout(map: VirtualWorkspaces())
        fresh.restore(saved, owners: owners)
        #expect(fresh.workspaces[one]?.kind == .side)
        #expect(fresh.workspaces[one]?.count == 2)
    }

    @Test func eachDisplayReturnsToTheWorkspaceItWasShowing() throws {
        var map = VirtualWorkspaces()
        map.sync(displays: ["A", "B"])
        _ = map.show(4, focusedDisplay: "A", isEmpty: true)
        let saved = TilingState().savedLayout(map: map)
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(SavedLayout.self, from: data)
        var fresh = VirtualWorkspaces()
        fresh.restore(visible: loaded.visible, homes: loaded.homes)
        fresh.sync(displays: ["A", "B"])
        #expect(fresh.number(on: "A") == 4)
        #expect(fresh.number(on: "B") == 2)
        #expect(fresh.home(of: 4) == "A")
    }
}
