import Foundation

/// What other tools can ask about workspaces, written by the app for the command line to read.
/// Holds workspace numbers, monitor positions and app names, never window titles.
struct WorkspaceReport: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var number: Int
        /// The monitor's position among the connected ones, from 1.
        var monitor: Int
        var isVisible: Bool
        var apps: [String]
    }

    var focused: Int?
    var workspaces: [Entry] = []

    static func build(
        map: VirtualWorkspaces, displays: [String], focused: Int?, appsByNumber: [Int: [String]]
    ) -> WorkspaceReport {
        var report = WorkspaceReport(focused: focused)
        for number in VirtualWorkspaces.numbers {
            let display = map.display(showing: number) ?? map.home(of: number) ?? displays.first
            let monitor = display.flatMap { displays.firstIndex(of: $0) }.map { $0 + 1 } ?? 1
            report.workspaces.append(
                Entry(
                    number: number, monitor: monitor, isVisible: map.display(showing: number) != nil,
                    apps: appsByNumber[number] ?? []))
        }
        return report
    }
}

/// The command line. Arguments follow AeroSpace's where they overlap, so scripts written for it
/// only need to call a different program.
enum TilingCommand: Equatable {
    enum Selection: Equatable {
        case all, focused
        case monitor(Int?)
    }

    struct UsageError: Error, Equatable {
        var message: String
    }

    case listWorkspaces(Selection, format: String)
    case listWindows(workspace: Int, format: String)
    case switchTo(Int)

    static let usage = """
        usage:
          tiling list-workspaces (--all | --focused | --monitor <n|all>) [--format <text>]
          tiling list-windows --workspace <1-9> [--format <text>]
          tiling workspace <1-9>
        """

    /// Nil when the arguments aren't a command, which means start the app.
    static func parse(_ arguments: [String]) -> Result<TilingCommand, UsageError>? {
        // Options starting with a dash come from macOS or Xcode when launching the app.
        guard let name = arguments.first, !name.hasPrefix("-") else { return nil }
        guard ["list-workspaces", "list-windows", "workspace"].contains(name) else { return .failure(error()) }
        let rest = Array(arguments.dropFirst())
        switch name {
        case "workspace":
            guard rest.count == 1, let number = workspaceNumber(rest[0]) else { return .failure(error()) }
            return .success(.switchTo(number))
        case "list-windows":
            guard let options = options(rest, known: ["--workspace", "--format"]),
                let number = options["--workspace"].flatMap(workspaceNumber)
            else { return .failure(error()) }
            return .success(.listWindows(workspace: number, format: options["--format"] ?? "%{app-name}"))
        default:
            return parseListWorkspaces(rest)
        }
    }

    private static func parseListWorkspaces(_ rest: [String]) -> Result<TilingCommand, UsageError> {
        var values = rest
        var selection: Selection?
        for flag in ["--all", "--focused"] {
            if let index = values.firstIndex(of: flag) {
                values.remove(at: index)
                selection = flag == "--all" ? .all : .focused
            }
        }
        guard let options = options(values, known: ["--monitor", "--format"]) else { return .failure(error()) }
        if let monitor = options["--monitor"] {
            if monitor == "all" {
                selection = .monitor(nil)
            } else if let number = Int(monitor), number > 0 {
                selection = .monitor(number)
            } else {
                return .failure(error())
            }
        }
        guard let selection else { return .failure(error()) }
        return .success(.listWorkspaces(selection, format: options["--format"] ?? "%{workspace}"))
    }

    private static func error() -> UsageError { UsageError(message: usage) }

    private static func workspaceNumber(_ text: String) -> Int? {
        Int(text).flatMap { VirtualWorkspaces.numbers.contains($0) ? $0 : nil }
    }

    /// Reads `--name value` pairs; nil if anything else is there.
    private static func options(_ values: [String], known: Set<String>) -> [String: String]? {
        guard values.count % 2 == 0 else { return nil }
        var result: [String: String] = [:]
        for index in stride(from: 0, to: values.count, by: 2) {
            guard known.contains(values[index]) else { return nil }
            result[values[index]] = values[index + 1]
        }
        return result
    }

    /// The lines a listing prints.
    func output(from report: WorkspaceReport) -> [String] {
        switch self {
        case .listWorkspaces(let selection, let format):
            let chosen = report.workspaces.filter { entry in
                switch selection {
                case .all, .monitor(nil): true
                case .focused: entry.number == report.focused
                case .monitor(let monitor?): entry.monitor == monitor
                }
            }
            if selection == .focused, chosen.isEmpty, let focused = report.focused {
                return [String(focused)]
            }
            return chosen.map { entry in
                format.replacingOccurrences(of: "%{workspace}", with: String(entry.number))
                    .replacingOccurrences(of: "%{monitor-appkit-nsscreen-screens-id}", with: String(entry.monitor))
            }
        case .listWindows(let workspace, let format):
            let apps = report.workspaces.first { $0.number == workspace }?.apps ?? []
            return apps.map { format.replacingOccurrences(of: "%{app-name}", with: $0) }
        case .switchTo:
            return []
        }
    }

    /// The configured program and arguments, with `{workspace}` filled in.
    static func hookArguments(_ hook: [String], focused: Int?) -> [String] {
        hook.map { $0.replacingOccurrences(of: "{workspace}", with: focused.map(String.init) ?? "") }
    }
}
