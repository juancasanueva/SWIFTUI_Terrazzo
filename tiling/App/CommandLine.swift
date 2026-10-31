import AppKit

/// Runs when the program is called with a command instead of being opened as the app.
enum TilingCommandLine {
    static let switchNotification = Notification.Name("com.juancasanueva.tiling.workspace")

    static var reportURL: URL {
        ConfigDirectory.url().appendingPathComponent("run/state.json")
    }

    /// Returns false when the arguments aren't a command, so the app should start.
    static func runIfCommand() -> Bool {
        guard let parsed = TilingCommand.parse(Array(CommandLine.arguments.dropFirst())) else { return false }
        switch parsed {
        case .failure(let error):
            fail(error.message, code: 2)
        case .success(.switchTo(let number)):
            let others = NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.juancasanueva.tiling")
                .filter { $0.processIdentifier != getpid() }
            guard !others.isEmpty else { fail("Tiling isn't running.", code: 1) }
            DistributedNotificationCenter.default().postNotificationName(
                switchNotification, object: String(number), userInfo: nil, deliverImmediately: true)
        case .success(let command):
            // The last report answers even before the app has started, as at login.
            let data = (try? Data(contentsOf: reportURL)) ?? Data()
            let report = (try? JSONDecoder().decode(WorkspaceReport.self, from: data)) ?? WorkspaceReport()
            for line in command.output(from: report) { print(line) }
        }
        return true
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
