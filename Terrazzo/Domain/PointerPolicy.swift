import CoreGraphics

/// Where the pointer should go when focus lands somewhere, if anywhere.
enum PointerPolicy {
    /// Counts as already over the window: the bar above it sits just outside.
    static let margin: CGFloat = 20

    static func destination(
        pointer: CGPoint, window: CGRect?, display: CGRect?, rules: AppSettings.MovePointer
    ) -> CGPoint? {
        if rules.onWindowFocus, let window, !window.insetBy(dx: -margin, dy: -margin).contains(pointer) {
            return CGPoint(x: window.midX, y: window.midY)
        }
        if rules.onMonitorChange, let display, !display.contains(pointer) {
            return CGPoint(x: display.midX, y: display.midY)
        }
        return nil
    }

    /// Whether one of this app's own windows keeps the pointer from the windows below it. Borders, backgrounds
    /// and notices ignore the mouse and let it through; Settings, the tour and the panels take it, and only
    /// inside their bounds: the tolerance around a point is for the resize handles of tiled windows.
    static func ownWindowTakesPointer(frame: CGRect, ignoresMouse: Bool, pointer: CGPoint) -> Bool {
        !ignoresMouse && frame.contains(pointer)
    }
}
