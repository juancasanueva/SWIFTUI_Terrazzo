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
        #expect(TerrazzoCommand.parse(["-psn_0_123456"]) == nil)
        #expect(TerrazzoCommand.parse(["-AppleLanguages", "(es)"]) == nil)
    }

    @Test(arguments: ["--help", "-h"])
    func helpPrintsTheUsage(flag: String) throws {
        let parsed = try #require(TerrazzoCommand.parse([flag]))
        #expect(try parsed.get() == .help)
        let lines = try output([flag])
        #expect(lines == TerrazzoCommand.usage.components(separatedBy: "\n"))
        #expect(lines.contains("  terrazzo --help"))
        #expect(lines.contains("  terrazzo --version"))
    }

    /// People put a symlink to the binary on their PATH; `Bundle.main` is then the symlink's folder.
    @Test func theVersionIsReadFromTheAppASymlinkPointsTo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Terrazzo.app/Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "test.terrazzo.\(UUID().uuidString)", "CFBundleExecutable": "Terrazzo",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "9.8.7",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let binary = contents.appendingPathComponent("MacOS/Terrazzo")
        try Data().write(to: binary)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("terrazzo")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)

        let info = TerrazzoCommandLine.appInfo(executable: link)
        #expect(TerrazzoCommand.versionLine(info) == "Terrazzo 9.8.7")
        #expect(TerrazzoCommand.versionLine(TerrazzoCommandLine.appInfo(executable: binary)) == "Terrazzo 9.8.7")
        #expect(TerrazzoCommandLine.appInfo(executable: nil) == nil)
    }

    @Test(arguments: ["--version", "-v"])
    func versionPrintsTheAppVersion(flag: String) throws {
        let parsed = try #require(TerrazzoCommand.parse([flag]))
        #expect(try parsed.get() == .version)
        #expect(TerrazzoCommand.versionLine(["CFBundleShortVersionString": "1.0.15"]) == "Terrazzo 1.0.15")
        #expect(TerrazzoCommand.versionLine(nil) == "Terrazzo")
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

    @Test func monitorsAreNumberedInMissionControlOrderLikeSketchyBar() {
        // NSScreen lists built-in, LG, Samsung; Mission Control lists built-in, Samsung, LG.
        let order = WorkspaceReport.monitorOrder(
            screens: ["builtin", "lg", "samsung"], managed: ["builtin", "samsung", "lg"])
        #expect(order == ["builtin", "samsung", "lg"])

        var map = VirtualWorkspaces()
        map.sync(displays: order)
        _ = map.show(4, focusedDisplay: "samsung", isEmpty: true)
        _ = map.show(7, focusedDisplay: "lg", isEmpty: true)
        let report = WorkspaceReport.build(map: map, displays: order, focused: nil, appsByNumber: [:])
        #expect(report.workspaces.first { $0.number == 4 }?.monitor == 2)
        #expect(report.workspaces.first { $0.number == 7 }?.monitor == 3)
    }

    @Test func screensMissionControlDoesNotListKeepTheirOrderAfterTheOthers() {
        #expect(WorkspaceReport.monitorOrder(screens: ["a", "b", "c"], managed: []) == ["a", "b", "c"])
        #expect(WorkspaceReport.monitorOrder(screens: ["a", "b", "c"], managed: ["c", "gone"]) == ["c", "a", "b"])
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
        ["--nope"], ["--all"], ["--help", "list-workspaces"], ["--version", "2"],
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
