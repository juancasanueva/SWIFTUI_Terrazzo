import CoreGraphics

/// Which numbered workspace each display shows. A number exists on one display at a time, so
/// pressing it goes to that workspace wherever it is.
struct VirtualWorkspaces: Equatable {
    static let numbers = 1...9

    private var visible: [String: Int] = [:]
    private var homes: [Int: String] = [:]
    private var connected: Set<String> = []

    func number(on display: String) -> Int {
        visible[display] ?? 1
    }

    func display(showing number: Int) -> String? {
        visible.first { $0.value == number }?.key
    }

    /// The display a workspace belongs to, showing or not, while that display is connected.
    func home(of number: Int) -> String? {
        homes[number].flatMap { connected.contains($0) ? $0 : nil }
    }

    mutating func adopt(_ number: Int, on display: String) {
        homes[number] = display
    }

    /// Follows connected displays, giving each new one the lowest workspace not in use.
    mutating func sync(displays: [String]) {
        connected = Set(displays)
        visible = visible.filter { connected.contains($0.key) }
        for display in displays where visible[display] == nil {
            let free = Self.numbers.first { number in
                self.display(showing: number) == nil && home(of: number) == nil
            }
            guard let free else { continue }
            visible[display] = free
            homes[free] = display
        }
    }

    /// Makes a workspace show and returns its display: where it already shows, else where its windows
    /// are, else the focused display.
    mutating func show(_ number: Int, focusedDisplay: String, isEmpty: Bool) -> String {
        if let showing = display(showing: number) { return showing }
        let target = isEmpty ? focusedDisplay : home(of: number) ?? focusedDisplay
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
