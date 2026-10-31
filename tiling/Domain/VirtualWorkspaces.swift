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
    /// last, else its lowest pinned one, else the lowest not in use.
    mutating func sync(displays: [String]) {
        remembered.merge(visible) { _, current in current }
        connected = Set(displays)
        visible = visible.filter { display, number in
            connected.contains(display) && (pinnedDisplay(of: number) ?? display) == display
        }
        for display in displays where visible[display] == nil {
            func usable(_ number: Int) -> Bool {
                self.display(showing: number) == nil && (pinnedDisplay(of: number) ?? display) == display
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
