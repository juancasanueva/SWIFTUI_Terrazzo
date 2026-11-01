import CoreGraphics
import Foundation

/// Which numbered workspace each display shows. A number exists on one display at a time, so
/// pressing it goes to that workspace wherever it is.
struct VirtualWorkspaces: Equatable {
    static let numbers = 1...9

    private var visible: [String: Int] = [:]
    private var homes: [Int: String] = [:]
    private var connected: Set<String> = []
    /// What each display showed last, so a display that reconnects returns to it.
    private var remembered: [String: Int] = [:]
    private var pins: [Int: String] = [:]

    func number(on display: String) -> Int {
        visible[display] ?? 1
    }

    func display(showing number: Int) -> String? {
        visible.first { $0.value == number }?.key
    }

    /// The display a workspace is pinned to, while that display is connected.
    func pinnedDisplay(of number: Int) -> String? {
        pins[number].flatMap { connected.contains($0) ? $0 : nil }
    }

    /// The display a workspace belongs to, showing or not, while that display is connected.
    func home(of number: Int) -> String? {
        pinnedDisplay(of: number) ?? homes[number].flatMap { connected.contains($0) ? $0 : nil }
    }

    var savedVisible: [String: Int] { visible.merging(remembered) { current, _ in current } }

    var savedHomes: [String: String] {
        Dictionary(uniqueKeysWithValues: homes.map { (String($0.key), $0.value) })
    }

    /// Brings back what was saved. The next `sync` shows each display's workspace again.
    mutating func restore(visible: [String: Int], homes: [String: String]) {
        remembered = visible
        for (text, display) in homes {
            if let number = Int(text), Self.numbers.contains(number) { self.homes[number] = display }
        }
    }

    mutating func adopt(_ number: Int, on display: String) {
        homes[number] = display
    }

    mutating func setPins(_ pins: [Int: String]) {
        self.pins = pins
    }

    /// Turns the config's "number to part of a display name" into display identifiers. A name that
    /// matches nothing connected leaves the workspace unpinned.
    static func resolvePins(_ names: [String: String], displays: [(uuid: String, name: String)]) -> [Int: String] {
        var pins: [Int: String] = [:]
        for (text, name) in names {
            guard let number = Int(text), numbers.contains(number), !name.isEmpty,
                let display = displays.first(where: { $0.name.range(of: name, options: .caseInsensitive) != nil })
            else { continue }
            pins[number] = display.uuid
        }
        return pins
    }

    /// Follows connected displays and pins. A display without a workspace returns to the one it showed
    /// last, else its lowest pinned one, else the lowest not in use. `occupied` names the display holding
    /// each workspace that has windows: taking one of those would leave its windows parked out of reach.
    mutating func sync(displays: [String], occupied: [Int: String] = [:]) {
        remembered.merge(visible) { _, current in current }
        connected = Set(displays)
        homes.merge(occupied) { _, holding in holding }
        visible = visible.filter { display, number in
            connected.contains(display) && (pinnedDisplay(of: number) ?? occupied[number] ?? display) == display
        }
        for display in displays where visible[display] == nil {
            func usable(_ number: Int) -> Bool {
                guard self.display(showing: number) == nil else { return false }
                if let pin = pinnedDisplay(of: number) { return pin == display }
                return (occupied[number] ?? display) == display
            }
            let chosen =
                remembered[display].flatMap { usable($0) ? $0 : nil }
                ?? Self.numbers.first { usable($0) && pinnedDisplay(of: $0) == display }
                ?? Self.numbers.first { usable($0) && home(of: $0) == nil }
                ?? Self.numbers.first(where: usable)
            guard let chosen else { continue }
            visible[display] = chosen
            homes[chosen] = display
        }
    }

    /// Makes a workspace show and returns its display: where it already shows, else where it is pinned,
    /// else where its windows are, else the focused display.
    mutating func show(_ number: Int, focusedDisplay: String, isEmpty: Bool) -> String {
        if let showing = display(showing: number) { return showing }
        let target = pinnedDisplay(of: number) ?? (isEmpty ? focusedDisplay : home(of: number) ?? focusedDisplay)
        visible[target] = number
        homes[number] = target
        return target
    }

    /// Where to park a window so that only its corner stays on its display. macOS keeps windows
    /// partly on screen, and a neighboring display would show the rest, so the corner is chosen to avoid one.
    static func hiddenOrigin(display: CGRect, others: [CGRect], windowSize: CGSize) -> CGPoint {
        let right = CGPoint(x: display.maxX - 1, y: display.maxY - 1)
        let parked = CGRect(origin: right, size: windowSize)
        if !others.contains(where: { $0.intersects(parked) }) { return right }
        return CGPoint(x: display.minX - windowSize.width + 1, y: display.maxY - 1)
    }
}

/// Remembers that the user just went to an empty workspace. With no window to focus, nothing else says
/// so: macOS keeps reporting the previous window for a while, and the pointer may be on another monitor.
struct EmptyWorkspaceFocus: Equatable {
    private(set) var display: String?
    private var windowAtSwitch: WindowID?
    /// Outlives a loss of focus: macOS can hand focus back to this window with no action from the user,
    /// for example when the menu bar is revealed.
    private var windowLeftBehind: WindowID?

    mutating func wentToEmpty(display: String, focused: WindowID?) {
        self.display = display
        windowAtSwitch = focused
        windowLeftBehind = focused ?? windowLeftBehind
    }

    /// Whether focus landing on a parked window means going to its workspace.
    func followsFocus(to window: WindowID) -> Bool {
        display == nil || window != windowLeftBehind
    }

    mutating func focusObserved(window: WindowID?, isShown: Bool) {
        guard display != nil else { return }
        guard let window else {
            windowAtSwitch = nil
            return
        }
        if isShown, window != windowAtSwitch { windowChosen() }
    }

    mutating func windowChosen() {
        display = nil
        windowAtSwitch = nil
        windowLeftBehind = nil
    }
}
