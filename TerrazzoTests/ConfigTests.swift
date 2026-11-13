import Foundation
import Testing
@testable import Terrazzo

@MainActor
struct ConfigTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aSavedIconChoiceIsIgnoredAndDroppedOnTheNextSave() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"iconStyle": "washi", "gap": 12}"#.utf8).write(to: url)
        let file = ConfigFile(url: url, defaults: AppSettings())

        let settings = try file.load()
        #expect(settings.gap == 12)

        try file.save(settings)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(!saved.contains("iconStyle"))
        #expect(saved.contains("\"gap\" : 12"))
    }

    @Test func directoryPrefersXDGAndFallsBackToDotConfig() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(ConfigDirectory.url(home: home, environment: [:]).path == "/Users/me/.config/terrazzo")
        #expect(
            ConfigDirectory.url(home: home, environment: ["XDG_CONFIG_HOME": "/x"]).path == "/x/terrazzo")
        #expect(
            ConfigDirectory.url(home: home, environment: ["XDG_CONFIG_HOME": ""]).path
                == "/Users/me/.config/terrazzo")
    }

    @Test func theBorderHugsARoundedWindow() {
        var highlight = AppSettings.Highlight()
        #expect(highlight.cornerRadius == 16)
        #expect(highlight.width == 3)
        // The border's inner edge follows the window, so its outer edge is rounder by its thickness.
        #expect(highlight.outerRadius == 19)
        highlight.width = 8
        highlight.cornerRadius = 26
        #expect(highlight.outerRadius == 34)
        highlight.cornerRadius = -5
        #expect(highlight.outerRadius == 8)
    }

    @Test func focusFollowsAMovedWindowUnlessTurnedOff() throws {
        #expect(AppSettings().followMovedWindow)

        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"followMovedWindow": false, "gap": 12}"#.utf8).write(to: url)
        let settings = try ConfigFile(url: url, defaults: AppSettings()).load()
        #expect(!settings.followMovedWindow)
        #expect(settings.gap == 12)
    }

    @Test func resizeStepDefaultsToFivePercent() {
        #expect(AppSettings().resizeStep == 5)
        #expect(AppSettings().resolvedResizeStep == 0.05)
        #expect(TilingPolicy().resizeStep == 0.05)
    }

    @Test func aHandEditedResizeStepIsKeptInARange() {
        var settings = AppSettings()
        settings.resizeStep = 0
        #expect(settings.resolvedResizeStep == 0.005)
        settings.resizeStep = 90
        #expect(settings.resolvedResizeStep == 0.25)
        settings.resizeStep = 1
        #expect(settings.resolvedResizeStep == 0.01)
    }

    @Test func resizeStepLoadsFromAPartialFile() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"resizeStep": 2}"#.utf8).write(to: url)
        #expect(try ConfigFile(url: url, defaults: AppSettings()).load().resizeStep == 2)
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

    @Test func aDisplayEdgesEntryCanNameJustOneSide() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"screenEdgesByDisplay": {"ABC": {"top": 50}}}"#.utf8).write(to: url)
        let settings = try ConfigFile(url: url, defaults: AppSettings()).load()
        #expect(settings.screenEdgesByDisplay == ["ABC": ScreenEdges(top: 50)])
    }

    @Test func aScreenEntryCanLeaveOutItsSizes() throws {
        let url = try temporaryDirectory().appendingPathComponent("screens.json")
        try Data(#"{"screens": {"ABC#1": {"count": 2}}}"#.utf8).write(to: url)
        let screens = try ConfigFile(url: url, defaults: ScreensFile()).load()
        #expect(screens.screens == ["ABC#1": ScreenPreferences(count: 2)])
    }

    @Test func aScreenEntryCanGiveOnlyOneKindOfSize() throws {
        let url = try temporaryDirectory().appendingPathComponent("screens.json")
        try Data(#"{"screens": {"ABC#1": {"overrides": {"tracks": {"columns:2": [0.6, 0.4]}}}}}"#.utf8)
            .write(to: url)
        let screens = try ConfigFile(url: url, defaults: ScreensFile()).load()
        #expect(screens.screens["ABC#1"]?.overrides == SizeOverrides(tracks: ["columns:2": [0.6, 0.4]]))
    }

    @Test func aWrongTypeInsideAnEntryIsStillMalformed() throws {
        let url = try temporaryDirectory().appendingPathComponent("settings.json")
        try Data(#"{"screenEdgesByDisplay": {"ABC": {"top": "high"}}}"#.utf8).write(to: url)
        #expect(throws: (any Error).self) { try ConfigFile(url: url, defaults: AppSettings()).load() }
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
        #expect(map.combo(for: .swapLeft)?.symbols == "⌃⇧←")
        #expect(map.combo(for: .swapRight)?.symbols == "⌃⇧→")
        #expect(map.combo(for: .swapUp)?.symbols == "⌃⇧↑")
        #expect(map.combo(for: .swapDown)?.symbols == "⌃⇧↓")
        #expect(map.combo(for: .makePrimary)?.symbols == "⌃⌥↩")
        #expect(map.combo(for: .nextInTile)?.symbols == "⌃N")
        #expect(map.combo(for: .previousInTile)?.symbols == "⌃⇧N")
        #expect(map.combo(for: .tabView)?.symbols == "⌃⇥")
        #expect(map.combo(for: .tabViewBackward)?.symbols == "⌃⇧⇥")
        #expect(map.combo(for: .alwaysFloat)?.symbols == "⌃⌥⇧F")
        #expect(map.combo(for: .cleanSpace)?.symbols == "⌃⌥P")
        #expect(map.combo(for: .tile5)?.symbols == "⌃⌥⌘5")
    }

    @Test func resizeUsesControlOptionArrowsWhateverThePrefix() {
        var map = ShortcutMap()
        #expect(map.combo(for: .resizeLeft)?.symbols == "⌃⌥←")
        #expect(map.combo(for: .resizeRight)?.symbols == "⌃⌥→")
        #expect(map.combo(for: .resizeUp)?.symbols == "⌃⌥↑")
        #expect(map.combo(for: .resizeDown)?.symbols == "⌃⌥↓")
        map.prefix = .controlShift
        #expect(map.combo(for: .resizeLeft)?.symbols == "⌃⌥←")
    }

    @Test func biggerAndSmallerHaveNoKeysUntilAssigned() {
        var map = ShortcutMap()
        #expect(map.combo(for: .bigger) == nil)
        #expect(map.combo(for: .smaller) == nil)
        map.bindings[ShortcutAction.bigger.rawValue] = "ctrl+opt+="
        #expect(map.combo(for: .bigger)?.string == "ctrl+opt+=")
        #expect(map.combo(for: .resetSizes)?.symbols == "⌃⌥0")
    }

    @Test func stackSwitchingStaysOnControlNWhateverThePrefix() {
        var map = ShortcutMap()
        map.prefix = .optionCommand
        #expect(map.combo(for: .nextInTile)?.symbols == "⌃N")
        #expect(map.combo(for: .previousInTile)?.symbols == "⌃⇧N")
    }

    @Test func floatingUsesControlTWhateverThePrefix() {
        var map = ShortcutMap()
        #expect(map.combo(for: .float)?.symbols == "⌃T")
        map.prefix = .optionCommand
        #expect(map.combo(for: .float)?.symbols == "⌃T")
    }

    @Test func alwaysFloatKeepsItsOwnKeys() {
        #expect(ShortcutMap().combo(for: .alwaysFloat)?.symbols == "⌃⌥⇧F")
    }

    @Test func focusModeUsesControlFWhateverThePrefix() {
        var map = ShortcutMap()
        #expect(map.combo(for: .focus)?.symbols == "⌃F")
        map.prefix = .optionCommand
        #expect(map.combo(for: .focus)?.symbols == "⌃F")
        #expect(map.combo(for: .alwaysFloat)?.symbols == "⌥⇧⌘F")
    }

    @Test func directionalFocusDefaultsToControlArrowsWhateverThePrefix() {
        var map = ShortcutMap()
        #expect(map.combo(for: .focusLeft)?.symbols == "⌃←")
        #expect(map.combo(for: .focusRight)?.symbols == "⌃→")
        #expect(map.combo(for: .focusUp)?.symbols == "⌃↑")
        #expect(map.combo(for: .focusDown)?.symbols == "⌃↓")
        map.prefix = .controlShift
        #expect(map.combo(for: .focusLeft)?.symbols == "⌃←")
    }

    @Test func directionalFocusCanBeRebound() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.focusLeft.rawValue] = "ctrl+h"
        #expect(map.combo(for: .focusLeft)?.symbols == "⌃H")
        map.bindings[ShortcutAction.focusRight.rawValue] = ShortcutMap.off
        #expect(map.combo(for: .focusRight) == nil)
    }

    @Test func prefixMovesEveryUnchangedShortcutExceptTabView() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.focus.rawValue] = "ctrl+shift+y"
        map.prefix = .optionCommand
        #expect(map.combo(for: .retile)?.symbols == "⌥⌘R")
        #expect(map.combo(for: .swapLeft)?.symbols == "⌃⇧←")
        #expect(map.combo(for: .focus)?.symbols == "⌃⇧Y")
        #expect(map.combo(for: .tabView)?.symbols == "⌃⇥")
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

    @Test func recordingAWindowCountShortcutChecksTheFiveKeysItBinds() throws {
        let map = ShortcutMap()
        // ⌃⇧K is free, but its modifiers put the five shortcuts on ⌃⇧1–5, which move a window to a workspace.
        let pressed = try #require(KeyCombo(string: "ctrl+shift+k"))
        let moves: [ShortcutAction] = [
            .moveToWorkspace1, .moveToWorkspace2, .moveToWorkspace3, .moveToWorkspace4, .moveToWorkspace5,
        ]
        #expect(map.conflicts(for: pressed, action: .tile1, system: []) == moves.map { .shortcut($0) })
        #expect(map.symbols(recording: pressed, for: .tile1) == "⌃⇧1–5")
        #expect(map.symbols(recording: pressed, for: .retile) == "⌃⇧K")
    }

    @Test func recordingAWindowCountShortcutChecksMacOSKeysOnTheFiveKeys() throws {
        let map = ShortcutMap()
        let pressed = try #require(KeyCombo(string: "opt+shift+k"))
        let taken = try #require(KeyCombo(string: "opt+shift+3"))
        #expect(map.conflicts(for: pressed, action: .tile1, system: [taken]) == [.system])
    }

    @Test func recordingAWindowCountShortcutIgnoresTheKeyPressedAndItsOwnKeys() throws {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.retile.rawValue] = "opt+shift+k"
        // The key pressed is dropped, so Retile keeping ⌥⇧K is no conflict.
        let pressed = try #require(KeyCombo(string: "opt+shift+k"))
        #expect(map.conflicts(for: pressed, action: .tile1, system: [pressed]).isEmpty)
        // Pressing the keys another window-count shortcut has changes nothing.
        let own = try #require(map.combo(for: .tile3))
        #expect(map.conflicts(for: own, action: .tile1, system: []).isEmpty)
    }

    @Test func tabViewBackwardFollowsTabViewWithShiftAdded() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.tabView.rawValue] = "cmd+e"
        #expect(map.combo(for: .tabViewBackward)?.symbols == "⇧⌘E")
    }

    @Test func tabViewOpenedBackwardIsHeldByItsOwnShortcutsModifiers() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.tabViewBackward.rawValue] = "opt+tab"
        #expect(map.tabViewHeldModifiers(openedBackward: true) == .option)
        #expect(map.tabViewHeldModifiers(openedBackward: false) == .control)
    }

    @Test func tabViewIsHeldByTheSameModifiersWhenBackwardFollowsForward() {
        var map = ShortcutMap()
        // Shift only tells backward from forward, so it isn't a key to keep holding.
        #expect(map.tabViewHeldModifiers(openedBackward: true) == .control)
        #expect(map.tabViewHeldModifiers(openedBackward: false) == .control)
        map.bindings[ShortcutAction.tabView.rawValue] = "cmd+e"
        #expect(map.tabViewHeldModifiers(openedBackward: true) == .command)
        #expect(map.tabViewHeldModifiers(openedBackward: false) == .command)
    }

    @Test func turningOffTabViewAlsoTurnsOffItsBackwardShortcut() {
        var map = ShortcutMap()
        map.bindings[ShortcutAction.tabView.rawValue] = ShortcutMap.off
        #expect(map.combo(for: .tabViewBackward) == nil)
    }

    @Test func conflictsListOwnAndSystemShortcuts() throws {
        let map = ShortcutMap()
        let own = try #require(KeyCombo(string: "ctrl+t"))
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
        #expect(map.combo(for: .focus)?.symbols == "⌃F")
    }
}
