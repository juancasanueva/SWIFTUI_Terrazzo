import Foundation

struct KeyModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: Int
    static let control = KeyModifiers(rawValue: 1)
    static let option = KeyModifiers(rawValue: 2)
    static let shift = KeyModifiers(rawValue: 4)
    static let command = KeyModifiers(rawValue: 8)

    /// In the order macOS displays modifiers.
    fileprivate static let ordered: [(KeyModifiers, String, String)] = [
        (.control, "ctrl", "⌃"), (.option, "opt", "⌥"), (.shift, "shift", "⇧"), (.command, "cmd", "⌘"),
    ]
}

/// The keys a shortcut can use. Raw values are the names used in `shortcuts.json`.
enum ShortcutKey: String, CaseIterable, Hashable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
    case n0 = "0", n1 = "1", n2 = "2", n3 = "3", n4 = "4", n5 = "5", n6 = "6", n7 = "7", n8 = "8", n9 = "9"
    case left, right, up, down, `return`, tab, space, escape
    case grave = "`", minus = "-", equal = "=", leftBracket = "[", rightBracket = "]"
    case backslash = "\\", semicolon = ";", quote = "'", comma = ",", period = ".", slash = "/"

    var symbol: String {
        switch self {
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .return: "↩"
        case .tab: "⇥"
        case .space: "␣"
        case .escape: "⎋"
        default: rawValue.uppercased()
        }
    }

    /// macOS virtual key code.
    var keyCode: UInt32 {
        Self.keyCodes[self] ?? 0
    }

    init?(keyCode: UInt32) {
        guard let match = Self.keyCodes.first(where: { $0.value == keyCode })?.key else { return nil }
        self = match
    }

    private static let keyCodes: [ShortcutKey: UInt32] = [
        .a: 0, .s: 1, .d: 2, .f: 3, .h: 4, .g: 5, .z: 6, .x: 7, .c: 8, .v: 9, .b: 11, .q: 12, .w: 13, .e: 14,
        .r: 15, .y: 16, .t: 17, .n1: 18, .n2: 19, .n3: 20, .n4: 21, .n6: 22, .n5: 23, .equal: 24, .n9: 25,
        .n7: 26, .minus: 27, .n8: 28, .n0: 29, .rightBracket: 30, .o: 31, .u: 32, .leftBracket: 33, .i: 34,
        .p: 35, .return: 36, .l: 37, .j: 38, .quote: 39, .k: 40, .semicolon: 41, .backslash: 42, .comma: 43,
        .slash: 44, .n: 45, .m: 46, .period: 47, .tab: 48, .space: 49, .grave: 50, .left: 123, .right: 124,
        .down: 125, .up: 126, .escape: 53,
    ]
}

struct KeyCombo: Hashable, Sendable {
    var key: ShortcutKey
    var modifiers: KeyModifiers

    init(key: ShortcutKey, modifiers: KeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses config syntax such as `ctrl+opt+left`.
    init?(string: String) {
        var parts = string.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.popLast(), let key = ShortcutKey(rawValue: keyName) else { return nil }
        var modifiers: KeyModifiers = []
        for part in parts {
            guard let match = KeyModifiers.ordered.first(where: { $0.1 == part }) else { return nil }
            modifiers.insert(match.0)
        }
        self.init(key: key, modifiers: modifiers)
    }

    var string: String {
        (KeyModifiers.ordered.filter { modifiers.contains($0.0) }.map(\.1) + [key.rawValue]).joined(separator: "+")
    }

    var symbols: String {
        KeyModifiers.ordered.filter { modifiers.contains($0.0) }.map(\.2).joined() + key.symbol
    }
}

enum ShortcutPrefix: String, Codable, CaseIterable, Sendable {
    case controlOption = "ctrl+opt"
    case optionCommand = "opt+cmd"
    case controlShift = "ctrl+shift"

    var modifiers: KeyModifiers {
        switch self {
        case .controlOption: [.control, .option]
        case .optionCommand: [.option, .command]
        case .controlShift: [.control, .shift]
        }
    }

    var symbols: String { KeyCombo(key: .a, modifiers: modifiers).symbols.replacingOccurrences(of: "A", with: "") }
}

enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case focusLeft, focusRight, focusUp, focusDown
    case swapLeft, swapRight, swapUp, swapDown
    case resizeLeft, resizeRight, resizeUp, resizeDown
    case makePrimary, nextWindow, previousWindow, nextInTile, previousInTile, tabView, tabViewBackward
    case bigger, smaller, resetSizes
    case float, alwaysFloat, focus, noPeek, cleanSpace, retile
    case tile1, tile2, tile3, tile4, tile5
    case workspace1, workspace2, workspace3, workspace4, workspace5, workspace6, workspace7, workspace8, workspace9
    case moveToWorkspace1, moveToWorkspace2, moveToWorkspace3, moveToWorkspace4, moveToWorkspace5
    case moveToWorkspace6, moveToWorkspace7, moveToWorkspace8, moveToWorkspace9

    fileprivate var defaultSuffix: (key: ShortcutKey, extra: KeyModifiers) {
        switch self {
        case .focusLeft: (.left, [])
        case .focusRight: (.right, [])
        case .focusUp: (.up, [])
        case .focusDown: (.down, [])
        case .resizeLeft: (.left, [])
        case .resizeRight: (.right, [])
        case .resizeUp: (.up, [])
        case .resizeDown: (.down, [])
        case .swapLeft: (.left, [])
        case .swapRight: (.right, [])
        case .swapUp: (.up, [])
        case .swapDown: (.down, [])
        case .makePrimary: (.return, [])
        case .nextWindow: (.rightBracket, [])
        case .previousWindow: (.leftBracket, [])
        case .nextInTile: (.grave, [])
        case .previousInTile: (.grave, .shift)
        case .tabView: (.tab, [])
        case .tabViewBackward: (.tab, .shift)
        case .bigger: (.equal, [])
        case .smaller: (.minus, [])
        case .resetSizes: (.n0, [])
        case .float: (.f, [])
        case .alwaysFloat: (.f, .shift)
        case .focus: (.z, [])
        case .noPeek: (.d, [])
        case .cleanSpace: (.p, [])
        case .retile: (.r, [])
        case .tile1: (.n1, .command)
        case .tile2: (.n2, .command)
        case .tile3: (.n3, .command)
        case .tile4: (.n4, .command)
        case .tile5: (.n5, .command)
        // Workspace shortcuts are built from their number in `combo(for:)`.
        default: (.n0, [])
        }
    }

    var workspaceNumber: Int? {
        rawValue.hasPrefix("workspace") ? Int(rawValue.dropFirst("workspace".count)) : nil
    }

    var moveWorkspaceNumber: Int? {
        rawValue.hasPrefix("moveToWorkspace") ? Int(rawValue.dropFirst("moveToWorkspace".count)) : nil
    }

    var isSwap: Bool {
        switch self {
        case .swapLeft, .swapRight, .swapUp, .swapDown: true
        default: false
        }
    }

    var resizeDirection: Direction? {
        switch self {
        case .resizeLeft: .left
        case .resizeRight: .right
        case .resizeUp: .up
        case .resizeDown: .down
        default: nil
        }
    }

    var focusDirection: Direction? {
        switch self {
        case .focusLeft: .left
        case .focusRight: .right
        case .focusUp: .up
        case .focusDown: .down
        default: nil
        }
    }

    var tileCount: Int? {
        switch self {
        case .tile1: 1
        case .tile2: 2
        case .tile3: 3
        case .tile4: 4
        case .tile5: 5
        default: nil
        }
    }

    var isTabView: Bool { self == .tabView || self == .tabViewBackward }
}

enum ShortcutConflict: Equatable, Sendable {
    case shortcut(ShortcutAction)
    case system
}

/// `~/.config/tiling/shortcuts.json`. Only keys the user changed are stored in `bindings`.
struct ShortcutMap: Codable, Equatable, Sendable {
    static let off = "off"

    var enabled = true
    var prefix: ShortcutPrefix = .controlOption
    /// Action name to key combo, or `off`.
    var bindings: [String: String] = [:]
    /// Modifiers shared by the window-count shortcuts, in config syntax without a key.
    var tileModifiers: String?

    func combo(for action: ShortcutAction) -> KeyCombo? {
        if let binding = bindings[action.rawValue] {
            return binding == Self.off ? nil : KeyCombo(string: binding)
        }
        if let number = action.workspaceNumber, let key = ShortcutKey(rawValue: "\(number)") {
            return KeyCombo(key: key, modifiers: .control)
        }
        if let number = action.moveWorkspaceNumber, let key = ShortcutKey(rawValue: "\(number)") {
            return KeyCombo(key: key, modifiers: [.control, .shift])
        }
        // Replaced by the arrows below; still available to anyone who assigns them keys.
        if action == .bigger || action == .smaller { return nil }
        let suffix = action.defaultSuffix
        if action.resizeDirection != nil {
            return KeyCombo(key: suffix.key, modifiers: [.control, .option])
        }
        // Moving goes with directional focus: same arrows and modifier, plus Shift, whatever the prefix.
        if action.isSwap {
            return KeyCombo(key: suffix.key, modifiers: [.control, .shift])
        }
        if action == .tabViewBackward {
            return combo(for: .tabView).map { KeyCombo(key: $0.key, modifiers: $0.modifiers.union(.shift)) }
        }
        // These don't follow the prefix either.
        if action == .tabView {
            return KeyCombo(key: suffix.key, modifiers: .control)
        }
        if action.focusDirection != nil {
            return KeyCombo(key: suffix.key, modifiers: .control)
        }
        if action == .focus {
            return KeyCombo(key: .f, modifiers: .control)
        }
        if action == .float {
            return KeyCombo(key: .t, modifiers: .control)
        }
        if action == .nextInTile {
            return KeyCombo(key: .n, modifiers: .control)
        }
        if action == .previousInTile {
            return KeyCombo(key: .n, modifiers: [.control, .shift])
        }
        if action.tileCount != nil, let tileModifiers,
            let shared = KeyCombo(string: "\(tileModifiers)+\(suffix.key.rawValue)") {
            return shared
        }
        return KeyCombo(key: suffix.key, modifiers: prefix.modifiers.union(suffix.extra))
    }

    /// The shortcuts to register with the system right now.
    var active: [ShortcutAction: KeyCombo] {
        guard enabled else { return [:] }
        var result: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            if let combo = combo(for: action) { result[action] = combo }
        }
        return result
    }

    mutating func reset(_ action: ShortcutAction) {
        bindings[action.rawValue] = nil
    }

    mutating func resetAll() {
        bindings = [:]
        tileModifiers = nil
        prefix = .controlOption
    }

    mutating func setTileModifiers(_ modifiers: KeyModifiers) {
        let combo = KeyCombo(key: .n1, modifiers: modifiers).string
        tileModifiers = String(combo.dropLast(2))
        for action in ShortcutAction.allCases where action.tileCount != nil { bindings[action.rawValue] = nil }
    }

    func conflicts(for combo: KeyCombo, action: ShortcutAction, system: Set<KeyCombo>) -> [ShortcutConflict] {
        var result: [ShortcutConflict] = ShortcutAction.allCases
            .filter { $0 != action && self.combo(for: $0) == combo }
            .map { .shortcut($0) }
        if system.contains(combo) { result.append(.system) }
        return result
    }

    /// Free keys with the current prefix, for offering when the chosen keys are taken.
    func suggestions(system: Set<KeyCombo>, limit: Int) -> [KeyCombo] {
        var result: [KeyCombo] = []
        for key in ShortcutKey.allCases {
            let candidate = KeyCombo(key: key, modifiers: prefix.modifiers)
            if conflicts(for: candidate, action: .retile, system: system).isEmpty, combo(for: .retile) != candidate {
                result.append(candidate)
            }
            if result.count == limit { break }
        }
        return result
    }
}
