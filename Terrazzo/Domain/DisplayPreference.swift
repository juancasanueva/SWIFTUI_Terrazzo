import CoreGraphics
import Foundation

struct DisplayInfo: Equatable {
    var uuid: String
    var name: String
    /// Whole screen, in window-system coordinates (origin at the top left of the main display).
    var frame: CGRect
    /// Below the menu bar and beside the Dock.
    var visibleFrame: CGRect
    var isBuiltIn = false
}

/// The displays a workspace prefers, best first. A candidate is part of a display name, `@builtin`
/// or `@external`. In the config, one candidate is written as a string and several as a list.
struct DisplayPreference: Codable, Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
    /// The Mac's own screen, whatever language its name is reported in.
    static let builtIn = "@builtin"
    /// Any connected display other than the Mac's own.
    static let external = "@external"

    var candidates: [String]

    init(_ candidates: [String]) {
        self.candidates = candidates
    }

    init(stringLiteral value: String) {
        candidates = [value]
    }

    init(arrayLiteral elements: String...) {
        candidates = elements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            candidates = [single]
        } else {
            candidates = try container.decode([String].self)
        }
    }

    /// One candidate stays a string, so a file without fallbacks is still read by older versions.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if candidates.count == 1 {
            try container.encode(candidates[0])
        } else {
            try container.encode(candidates)
        }
    }

    /// The display of the first candidate that is connected. `named` holds the displays that some
    /// workspace asks for by name: `@external` leaves those to their own workspaces when it can.
    func display(among displays: [DisplayInfo], named: Set<String> = []) -> DisplayInfo? {
        for candidate in candidates {
            if let display = Self.display(matching: candidate, among: displays, named: named) { return display }
        }
        return nil
    }

    /// The connected displays this preference asks for by name.
    func namedDisplays(among displays: [DisplayInfo]) -> [String] {
        candidates.filter { !Self.isRole($0) }.compactMap { Self.display(named: $0, among: displays)?.uuid }
    }

    private static func isRole(_ candidate: String) -> Bool {
        [builtIn, external].contains(candidate.lowercased())
    }

    private static func display(
        matching candidate: String, among displays: [DisplayInfo], named: Set<String>
    ) -> DisplayInfo? {
        switch candidate.lowercased() {
        case builtIn:
            return displays.first(where: \.isBuiltIn)
        case external:
            let externals = displays.filter { !$0.isBuiltIn }
                .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            return externals.first { !named.contains($0.uuid) } ?? externals.first
        default:
            return display(named: candidate, among: displays)
        }
    }

    /// Part of the name is enough, in any case.
    private static func display(named name: String, among displays: [DisplayInfo]) -> DisplayInfo? {
        guard !name.isEmpty else { return nil }
        return displays.first { $0.name.range(of: name, options: .caseInsensitive) != nil }
    }
}

/// How the settings window edits a preference: the display asked for, then what to use without it.
extension DisplayPreference {
    var primary: String { candidates.first ?? "" }

    var fallbacks: [String] { Array(candidates.dropFirst()) }

    /// Nil for no display at all, which is "Any display".
    func choosing(primary: String) -> DisplayPreference? {
        primary.isEmpty ? nil : DisplayPreference([primary] + fallbacks.filter { $0 != primary })
    }

    func choosing(fallbacks: [String]) -> DisplayPreference {
        DisplayPreference(candidates.prefix(1) + fallbacks)
    }
}

extension AppSettings {
    /// These settings with the built-in display named by role wherever a workspace asks for it by its
    /// full name. macOS reports that name in the language in use, so it stops matching when that changes.
    func namingBuiltInDisplayByRole(_ name: String?) -> AppSettings {
        guard let name, !name.isEmpty else { return self }
        var updated = self
        updated.workspaceDisplays = workspaceDisplays.mapValues { preference in
            DisplayPreference(preference.candidates.map { $0 == name ? DisplayPreference.builtIn : $0 })
        }
        return updated
    }
}
