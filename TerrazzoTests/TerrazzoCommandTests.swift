import Foundation
import Testing
@testable import Terrazzo

@MainActor
struct TerrazzoCommandTests {
    private let report = WorkspaceReport(
        focused: 3,
        workspaces: [
            WorkspaceReport.Entry(number: 1, monitor: 1, isVisible: true, apps: ["WezTerm", "Zen"]),
            WorkspaceReport.Entry(number: 3, monitor: 1, isVisible: false, apps: ["Rex"]),
            WorkspaceReport.Entry(number: 7, monitor: 2, isVisible: true, apps: []),
        ])

    private func output(_ arguments: [String]) throws -> [String] {
        let parsed = try #require(TerrazzoCommand.parse(arguments))
        return try parsed.get().output(from: report)
    }

    @Test func noArgumentsStartsTheApp() {
        #expect(TerrazzoCommand.parse([]) == nil)
        #expect(TerrazzoCommand.parse(["-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    }

    @Test func anUnknownWordIsAnErrorRatherThanStartingTheApp() throws {
        let parsed = try #require(TerrazzoCommand.parse(["nonsense"]))
        #expect(throws: TerrazzoCommand.UsageError.self) { try parsed.get() }
    }

    @Test func listsAllWorkspaces() throws {
        #expect(try output(["list-workspaces", "--all"]) == ["1", "3", "7"])
    }

    @Test func listsTheFocusedWorkspace() throws {
        #expect(try output(["list-workspaces", "--focused"]) == ["3"])
    }

    @Test func noFocusedWorkspacePrintsNothing() throws {
        let parsed = try #require(TerrazzoCommand.parse(["list-workspaces", "--focused"]))
        #expect(try parsed.get().output(from: WorkspaceReport()) == [])
    }

    @Test func mapsWorkspacesToMonitorsInTheFormatScriptsUse() throws {
        let lines = try output([
            "list-workspaces", "--monitor", "all", "--format", "%{workspace} %{monitor-appkit-nsscreen-screens-id}",
        ])
        #expect(lines == ["1 1", "3 1", "7 2"])
    }

    @Test func filtersByMonitor() throws {
        #expect(try output(["list-workspaces", "--monitor", "2"]) == ["7"])
    }

    @Test func listsTheAppsOfAWorkspace() throws {
        #expect(try output(["list-windows", "--workspace", "1", "--format", "%{app-name}"]) == ["WezTerm", "Zen"])
        #expect(try output(["list-windows", "--workspace", "1"]) == ["WezTerm", "Zen"])
    }

    @Test func anEmptyWorkspaceListsNoApps() throws {
        #expect(try output(["list-windows", "--workspace", "7"]) == [])
    }

    @Test func aWorkspaceNotInTheReportListsNoApps() throws {
        #expect(try output(["list-windows", "--workspace", "9"]) == [])
    }

    @Test func parsesSwitching() throws {
        let parsed = try #require(TerrazzoCommand.parse(["workspace", "4"]))
        #expect(try parsed.get() == .switchTo(4))
    }

    @Test(arguments: [
        ["workspace"], ["workspace", "0"], ["workspace", "10"], ["workspace", "x"], ["list-workspaces"],
        ["list-workspaces", "--nope"], ["list-workspaces", "--monitor"], ["list-windows"],
        ["list-windows", "--workspace", "x"], ["list-windows", "--format", "%{app-name}"],
    ])
    func badArgumentsAreErrors(arguments: [String]) throws {
        let parsed = try #require(TerrazzoCommand.parse(arguments))
        #expect(throws: TerrazzoCommand.UsageError.self) { try parsed.get() }
    }

    @Test func reportRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(WorkspaceReport.self, from: data) == report)
    }

    @Test func theHookReplacesTheWorkspaceNumber() {
        let hook = ["/bin/x", "--trigger", "change", "FOCUSED_WORKSPACE={workspace}"]
        #expect(
            TerrazzoCommand.hookArguments(hook, focused: 3) == ["/bin/x", "--trigger", "change", "FOCUSED_WORKSPACE=3"])
        #expect(
            TerrazzoCommand.hookArguments(hook, focused: nil) == ["/bin/x", "--trigger", "change", "FOCUSED_WORKSPACE="])
        #expect(TerrazzoCommand.hookArguments([], focused: 1).isEmpty)
    }

    @Test func theHookDefaultsToNothing() {
        #expect(AppSettings().onWorkspaceChange.isEmpty)
    }

    @Test func aConnectedReportNamesEveryWorkspace() {
        let map = { () -> VirtualWorkspaces in
            var map = VirtualWorkspaces()
            map.setPins([1: "A", 7: "B"])
            map.sync(displays: ["A", "B"])
            return map
        }()
        let built = WorkspaceReport.build(
            map: map, displays: ["A", "B"], focused: 7, appsByNumber: [1: ["Zen"]])
        #expect(built.workspaces.map(\.number) == Array(1...9))
        #expect(built.workspaces[0].monitor == 1)
        #expect(built.workspaces[0].apps == ["Zen"])
        #expect(built.workspaces[6].monitor == 2)
        #expect(built.workspaces[6].isVisible)
        #expect(built.focused == 7)
    }
}
