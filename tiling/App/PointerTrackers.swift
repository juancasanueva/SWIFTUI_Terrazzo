import AppKit

/// Watches mouse drags on tiled windows and turns them into swaps, moves and resizes.
final class DragTracker {
    private enum Kind { case move, resize }

    private unowned let controller: AppController
    private var monitors: [Any] = []
    private var window: WindowID?
    private var startFrame: CGRect = .zero
    private var kind: Kind?

    init(controller: AppController) {
        self.controller = controller
    }

    /// True from the press on a tiled window until release; automatic placement waits meanwhile.
    /// Global monitors miss a release over this app's own panels, so the button state has the last word.
    var isActive: Bool {
        guard window != nil else { return false }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            released()
            return false
        }
        return true
    }

    func start() {
        guard monitors.isEmpty else { return }
        add(.leftMouseDown) { [weak self] in self?.pressed() }
        add(.leftMouseDragged) { [weak self] in self?.dragged() }
        add(.leftMouseUp) { [weak self] in self?.released() }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        window = nil
        kind = nil
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ action: @escaping () -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in action() }) {
            monitors.append(monitor)
        }
    }

    private func pressed() {
        // Resize handles reach a few points outside the window.
        guard let id = controller.tiledWindow(at: Displays.pointerLocation(), tolerance: 6),
            let frame = controller.ax.currentFrame(of: id)
        else { return }
        controller.windowPressed()
        window = id
        startFrame = frame
        kind = nil
    }

    private func dragged() {
        guard let id = window, let frame = controller.ax.currentFrame(of: id) else { return }
        if kind == nil {
            if abs(frame.width - startFrame.width) > 1 || abs(frame.height - startFrame.height) > 1 {
                kind = .resize
            } else if abs(frame.minX - startFrame.minX) > 1 || abs(frame.minY - startFrame.minY) > 1 {
                kind = .move
            }
        }
        if kind == .move {
            controller.dragHover(id: id, pointer: Displays.pointerLocation(), modifiers: NSEvent.modifierFlags)
        }
    }

    private func released() {
        guard let id = window else { return }
        let finished = kind
        window = nil
        kind = nil
        switch finished {
        case .move:
            controller.finishMove(id: id, pointer: Displays.pointerLocation(), modifiers: NSEvent.modifierFlags)
        case .resize:
            if let frame = controller.ax.currentFrame(of: id) { controller.finishResize(id: id, frame: frame) }
        case nil:
            break
        }
        controller.dragEnded()
    }
}

/// Activates the window the pointer rests on. Only pointer movement arms it, so after a key press
/// the pointer must move before it activates anything again.
final class HoverFocus {
    private static let restDelay: TimeInterval = 0.2

    private unowned let controller: AppController
    private var monitor: Any?
    private var timer: Timer?

    init(controller: AppController) {
        self.controller = controller
    }

    func update(enabled: Bool) {
        if enabled, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.moved() }
        } else if !enabled, let existing = monitor {
            NSEvent.removeMonitor(existing)
            monitor = nil
            timer?.invalidate()
        }
    }

    private func moved() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.restDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.rested() }
        }
    }

    private func rested() {
        guard NSEvent.pressedMouseButtons == 0,
            let id = controller.tiledWindow(at: Displays.pointerLocation()),
            id != controller.ax.focusedWindow()
        else { return }
        controller.ax.focus(id)
    }
}
