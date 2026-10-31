import CoreGraphics
import Foundation

enum HighlightStyle: String, Codable, CaseIterable, Sendable {
    case none, activeBorder, allBorders, glow
}

enum CleanBackground: String, Codable, CaseIterable, Sendable {
    case graphite, mist, stone
}

enum AppearanceChoice: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

enum IconStyle: String, Codable, CaseIterable, Sendable {
    case washi, lantern, indigo, sunset, torii, glass, focus
}

struct ScreenEdges: Codable, Equatable, Sendable {
    var top: CGFloat = 0
    var left: CGFloat = 0
    var bottom: CGFloat = 0
    var right: CGFloat = 0
}

/// `~/.config/tiling/settings.json`
struct AppSettings: Codable, Equatable, Sendable {
    struct NoPeek: Codable, Equatable, Sendable {
        var dim: Double = 50
        var blur = true
    }

    struct Highlight: Codable, Equatable, Sendable {
        var style: HighlightStyle = .activeBorder
        var color = "#FF9500"
        var width: Double = 3
    }

    var tilingEnabled = true
    var setupFinished = false
    var stackNoticeShown = false
    /// Unset means Grid on landscape screens and Rows on vertical ones.
    var layout: LayoutKind?
    var windowsPerScreen = 3
    var mainSize: MainSize = .half
    var whenFull: FullScreenBehavior = .stack
    var movingIntoFull: MoveIntoFullBehavior = .swap
    var gap: Double = 8
    /// Space kept clear on every screen, for bars drawn by other apps.
    var screenEdges = ScreenEdges()
    /// Space kept clear on one screen, by display UUID. Wins over `screenEdges`.
    var screenEdgesByDisplay: [String: ScreenEdges] = [:]
    var highlight = Highlight()
    var noPeek = NoPeek()
    var hoverFocus = false
    var cleanBackground: CleanBackground = .graphite
    var appearance: AppearanceChoice = .system
    /// Language code, or unset to follow the Mac.
    var language: String?
    var openAtLogin = true
    var iconStyle: IconStyle = .washi
}

/// `~/.config/tiling/apps.json`
struct AppRules: Codable, Equatable, Sendable {
    static let defaultExcluded = [
        "com.apple.calculator", "com.apple.Stickies", "com.apple.systempreferences",
        "com.apple.ScreenContinuity", "com.apple.PhotoBooth",
    ]

    /// Apps whose windows stay where the user put them.
    var excluded = Self.defaultExcluded
    /// Smallest sizes apps accepted, by bundle identifier.
    var learnedMinimums: [String: CGSize] = [:]
}

/// `~/.config/tiling/screens.json`, one entry per screen and Space.
struct ScreenPreferences: Codable, Equatable, Sendable {
    var kind: LayoutKind?
    var count: Int?
    var overrides = SizeOverrides()
}

struct ScreensFile: Codable, Equatable, Sendable {
    var screens: [String: ScreenPreferences] = [:]

    static func id(_ key: WorkspaceKey) -> String { "\(key.display)#\(key.space)" }
}
