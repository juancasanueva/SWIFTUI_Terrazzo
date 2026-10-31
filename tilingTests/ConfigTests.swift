import Foundation
import Testing
@testable import tiling

@MainActor
struct ConfigTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func directoryPrefersXDGAndFallsBackToDotConfig() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(ConfigDirectory.url(home: home, environment: [:]).path == "/Users/me/.config/tiling")
        #expect(
            ConfigDirectory.url(home: home, environment: ["XDG_CONFIG_HOME": "/x"]).path == "/x/tiling")
        #expect(
            ConfigDirectory.url(home: home, environment: ["XDG_CONFIG_HOME": ""]).path
                == "/Users/me/.config/tiling")
    }

    @Test func missingFileYieldsDefaults() throws {
        let file = ConfigFile<AppSettings>(url: try temporaryDirectory().appendingPathComponent("settings.json"), defaults: AppSettings())
        #expect(try file.load() == AppSettings())
    }

    @Test func missingKeysTakeDefaultsAndPresentKeysWin() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"gap": 20, "noPeek": {"dim": 70}}"#.utf8).write(to: url)
        let settings = try ConfigFile(url: url, defaults: AppSettings()).load()
        #expect(settings.gap == 20)
        #expect(settings.noPeek.dim == 70)
        #expect(settings.noPeek.blur == true)
        #expect(settings.windowsPerScreen == 3)
    }

    @Test func savedFileIsReadableJSONAndRoundTrips() throws {
        let url = try temporaryDirectory().appendingPathComponent("nested/settings.json")
        let file = ConfigFile(url: url, defaults: AppSettings())
        var settings = AppSettings()
        settings.gap = 12
        settings.layout = .side
        try file.save(settings)
        #expect(try file.load() == settings)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("\"gap\" : 12"))
    }

    @Test func malformedFileThrowsAndIsNeverOverwritten() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: url)
        let file = ConfigFile(url: url, defaults: AppSettings())
        #expect(throws: (any Error).self) { try file.load() }
        #expect(throws: ConfigFileError.malformed) { try file.save(AppSettings()) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ not json")
    }

    @Test func wrongTypeIsMalformedRatherThanSilentlyReset() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"gap": "wide"}"#.utf8).write(to: url)
        #expect(throws: (any Error).self) { try ConfigFile(url: url, defaults: AppSettings()).load() }
    }

    // MARK: Key combos

    @Test func combosParseAndPrintForConfigAndDisplay() throws {
        let combo = try #require(KeyCombo(string: "ctrl+opt+left"))
        #expect(combo.modifiers == [.control, .option])
        #expect(combo.key == .left)
        #expect(combo.string == "ctrl+opt+left")
        #expect(combo.symbols == "⌃⌥←")
        #expect(KeyCombo(string: "ctrl+nonsense") == nil)
        #expect(KeyCombo(string: "ctrl+opt") == nil)
    }

    @Test func modifierOrderDoesNotMatter() {
        #expect(KeyCombo(string: "opt+ctrl+f") == KeyCombo(string: "ctrl+opt+f"))
    }

    // MARK: Shortcut map

    @Test func defaultsMatchTheDocumentedTable() {
        let map = ShortcutMap()
        #expect(map.combo(for: .swapLeft)?.symbols == "⌃⌥←")
        #expect(map.combo(for: .makePrimary)?.symbols == "⌃⌥↩")
        #expect(map.combo(for: .nextInTile)?.symbols == "⌃⌥`")
        #expect(map.combo(for: .previousInTile)?.symbols == "⌃⌥⇧`")
        #expect(map.combo(for: .tabView)?.symbols == "⌥⇥")
        #expect(map.combo(for: .tabViewBackward)?.symbols == "⌥⇧⇥")
        #expect(map.combo(for: .alwaysFloat)?.symbols == "⌃⌥⇧F")
        #expect(map.combo(for: .cleanSpace)?.symbols == "⌃⌥P")
        #expect(map.combo(for: .tile5)?.symbols == "⌃⌥⌘5")
    }

    @Test func prefixMovesEveryUnchangedShortcutExceptTabView() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.focus.rawValue] = "ctrl+shift+y"
        map.prefix = .optionCommand
        #expect(map.combo(for: .swapLeft)?.symbols == "⌥⌘←")
        #expect(map.combo(for: .focus)?.symbols == "⌃⇧Y")
        #expect(map.combo(for: .tabView)?.symbols == "⌥⇥")
    }

    @Test func turningOffKeepsTheActionListedWithoutKeys() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.retile.rawValue] = ShortcutMap.off
        #expect(map.combo(for: .retile) == nil)
        map.reset(.retile)
        #expect(map.combo(for: .retile)?.symbols == "⌃⌥R")
    }

    @Test func masterSwitchDisablesRegistrationButKeepsTheList() {
        var map = ShortcutMap()
        map.enabled = false
        #expect(map.active.isEmpty)
        #expect(map.combo(for: .retile) != nil)
    }

    @Test func windowCountShortcutsChangeTogether() {
        var map = ShortcutMap()
        map.setTileModifiers([.control, .shift])
        #expect(map.combo(for: .tile1)?.symbols == "⌃⇧1")
        #expect(map.combo(for: .tile5)?.symbols == "⌃⇧5")
    }

    @Test func tabViewBackwardFollowsTabViewWithShiftAdded() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.tabView.rawValue] = "cmd+e"
        #expect(map.combo(for: .tabViewBackward)?.symbols == "⇧⌘E")
    }

    @Test func turningOffTabViewAlsoTurnsOffItsBackwardShortcut() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.tabView.rawValue] = ShortcutMap.off
        #expect(map.combo(for: .tabViewBackward) == nil)
    }

    @Test func conflictsListOwnAndSystemShortcuts() throws {
        let map = ShortcutMap()
        let own = try #require(KeyCombo(string: "ctrl+opt+f"))
        #expect(map.conflicts(for: own, action: .retile, system: []) == [.shortcut(.float)])
        #expect(map.conflicts(for: own, action: .float, system: []).isEmpty)
        let system = try #require(KeyCombo(string: "cmd+space"))
        #expect(map.conflicts(for: system, action: .retile, system: [system]) == [.system])
    }

    @Test func suggestionsAreFreeOfOwnAndSystemKeys() throws {
        let map = ShortcutMap()
        let taken = try #require(KeyCombo(string: "ctrl+opt+a"))
        let suggestions = map.suggestions(system: [taken], limit: 3)
        #expect(suggestions.count == 3)
        #expect(!suggestions.contains(taken))
        #expect(suggestions.allSatisfy { map.conflicts(for: $0, action: .retile, system: [taken]).isEmpty })
    }

    @Test func partialShortcutsFileLoadsWithDefaults() throws {
        let url = try temporaryDirectory().appendingPathComponent("shortcuts.json")
        try Data(#"{"bindings": {"retile": "ctrl+opt+t"}}"#.utf8).write(to: url)
        let map = try ConfigFile(url: url, defaults: ShortcutMap()).load()
        #expect(map.combo(for: .retile)?.symbols == "⌃⌥T")
        #expect(map.combo(for: .focus)?.symbols == "⌃⌥Z")
    }
}
