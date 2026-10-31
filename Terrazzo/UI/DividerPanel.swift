import AppKit

struct StackedWindow: Equatable {
    var id: WindowID
    var frame: CGRect
}

enum DividerOrder: Equatable {
    case above(WindowID)
    case below(WindowID)
}

enum DividerMetrics {
    struct Appearance: Equatable {
        var thickness: CGFloat
        var opacity: CGFloat
    }

    /// Among ordinary windows, below the grips that share the same gaps, so `order` can keep it under others.
    static let level = NSWindow.Level.normal
    static let minimumHitThickness: CGFloat = 12
    static let handleLength: CGFloat = 100
    static let color = NSColor.white

    /// Under the frontmost untiled window reaching into the gap, so a dialog or float keeps its clicks even when
    /// a tile was raised above it. Otherwise above every tile. Nothing when no tile is on screen to resize.
    static func order(hitFrame: CGRect, tiles: Set<WindowID>, frontToBack: [StackedWindow]) -> DividerOrder? {
        if let cover = frontToBack.first(where: { !tiles.contains($0.id) && $0.frame.intersects(hitFrame) }) {
            return .below(cover.id)
        }
        return frontToBack.first { tiles.contains($0.id) }.map { .above($0.id) }
    }

    static func appearance(emphasized: Bool) -> Appearance {
        emphasized ? Appearance(thickness: 6, opacity: 1) : Appearance(thickness: 3, opacity: 0.25)
    }

    /// A short handle at the middle of the gap. A narrow gap reaches a little over the windows beside it.
    static func hitFrame(of divider: LayoutDivider) -> CGRect {
        let frame = divider.frame
        let thickness = divider.movesHorizontally ? frame.width : frame.height
        let length = divider.movesHorizontally ? frame.height : frame.width
        let outset = max(minimumHitThickness - thickness, 0) / 2
        let inset = max(length - handleLength, 0) / 2
        return divider.movesHorizontally
            ? frame.insetBy(dx: -outset, dy: inset) : frame.insetBy(dx: inset, dy: -outset)
    }

    static func barFrame(in bounds: CGRect, movesHorizontally: Bool, thickness: CGFloat) -> CGRect {
        movesHorizontally
            ? CGRect(x: bounds.midX - thickness / 2, y: bounds.minY, width: thickness, height: bounds.height)
            : CGRect(x: bounds.minX, y: bounds.midY - thickness / 2, width: bounds.width, height: thickness)
    }
}

/// Keeps the divider where it was grabbed relative to the pointer, wherever on its width the press landed.
struct DividerDrag: Equatable {
    private let offset: CGFloat

    init(position: CGFloat, pointer: CGFloat) {
        offset = position - pointer
    }

    func position(for pointer: CGFloat) -> CGFloat {
        pointer + offset
    }
}

/// The bar in the gap between two tiles: faint until the pointer is on it, and draggable to resize them.
final class DividerPanel: NSPanel {
    private let handle: DividerHandleView

    init(id: DividerID, controller: AppController) {
        handle = DividerHandleView(id: id, controller: controller)
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = DividerMetrics.level
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // By default macOS sends clicks on transparent pixels to the window below.
        ignoresMouseEvents = false
        contentView = handle
    }

    func show(_ divider: LayoutDivider, order placement: DividerOrder?) {
        setFrame(Displays.toAppKit(DividerMetrics.hitFrame(of: divider)), display: true)
        handle.update(divider)
        switch placement {
        case .above(let window): order(.above, relativeTo: Int(window))
        case .below(let window): order(.below, relativeTo: Int(window))
        case nil: orderOut(nil)
        }
    }

    /// Going away sends no exit event, so the resize cursor has to be given back here.
    func remove() {
        handle.releaseCursor()
        orderOut(nil)
    }
}

private final class DividerHandleView: NSView {
    private let id: DividerID
    private weak var controller: AppController?
    private let bar = CALayer()
    private var position: CGFloat = 0
    private var isHovering = false
    private var drag: DividerDrag?

    init(id: DividerID, controller: AppController) {
        self.id = id
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var cursor: NSCursor { id.movesHorizontally ? .columnResize : .rowResize }

    /// The panel never becomes key, so the first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func update(_ divider: LayoutDivider) {
        position = divider.position
        // A release can be lost when the panel moves away mid-drag; the button state has the last word.
        if NSEvent.pressedMouseButtons & 1 == 0 { drag = nil }
        // A layout change can move the panel out from under a pointer that never moved.
        if drag == nil, isHovering, let window, !window.frame.contains(NSEvent.mouseLocation) {
            releaseCursor()
        }
        refresh(animated: false)
    }

    func releaseCursor() {
        guard isHovering || drag != nil else { return }
        isHovering = false
        NSCursor.arrow.set()
    }

    override func layout() {
        super.layout()
        refresh(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        cursor.set()
        refresh(animated: true)
    }

    // Another app can change the cursor while it is frontmost, so it is set again as the pointer moves.
    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if drag == nil { NSCursor.arrow.set() }
        refresh(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        drag = DividerDrag(position: position, pointer: pointerPosition)
        cursor.set()
        refresh(animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        cursor.set()
        controller?.moveDivider(id, to: drag.position(for: pointerPosition))
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        if !isHovering { NSCursor.arrow.set() }
        refresh(animated: true)
        controller?.finishDividerDrag(id)
    }

    private var pointerPosition: CGFloat {
        let pointer = Displays.pointerLocation()
        return id.movesHorizontally ? pointer.x : pointer.y
    }

    private func refresh(animated: Bool) {
        let appearance = DividerMetrics.appearance(emphasized: isHovering || drag != nil)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setDisableActions(!animated)
        bar.frame = DividerMetrics.barFrame(
            in: bounds, movesHorizontally: id.movesHorizontally, thickness: appearance.thickness)
        bar.cornerRadius = appearance.thickness / 2
        bar.backgroundColor = DividerMetrics.color.withAlphaComponent(appearance.opacity).cgColor
        CATransaction.commit()
    }
}
