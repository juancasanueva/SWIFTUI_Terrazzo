import AppKit

/// Runs when the program is called with a command instead of being opened as the app.
enum TerrazzoCommandLine {
    static let switchNotification = Notification.Name("com.juancasanueva.terrazzo.workspace")

    static var reportURL: URL {
        ConfigDirectory.url().appendingPathComponent("run/state.json")
    }

    /// Returns false when the arguments aren't a command, so the app should start.
    static func runIfCommand() -> Bool {
        guard let parsed = TerrazzoCommand.parse(Array(CommandLine.arguments.dropFirst())) else { return false }
        switch parsed {
        case .failure(let error):
            fail(error.message, code: 2)
        case .success(.version):
            let info = appInfo(executable: Bundle.main.executableURL) ?? Bundle.main.infoDictionary
            print(TerrazzoCommand.versionLine(info))
        case .success(.switchTo(let number)):
            let others = NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.juancasanueva.terrazzo")
                .filter { $0.processIdentifier != getpid() }
            guard !others.isEmpty else { fail("Terrazzo isn't running.", code: 1) }
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

    /// The Info.plist of the app holding the binary. Run through a symlink, as from a folder on the
    /// PATH, `Bundle.main` is the symlink's folder and knows no version.
    static func appInfo(executable: URL?) -> [String: Any]? {
        guard let executable else { return nil }
        let app = executable.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app)?.infoDictionary
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
