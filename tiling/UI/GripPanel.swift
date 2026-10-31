import AppKit
import SwiftUI

@Observable
final class GripModel {
    var windows: [WindowID] = []
    var isActive = false
    var expanded = false
    var style = AppSettings.StackBar()
    var onExpansionChange: ((Bool) -> Void)?
}

/// Sizes of the handle above a tile, chosen so each segment is easy to hit.
enum GripMetrics {
    static let hitHeight: CGFloat = 24
    static let barHeight: CGFloat = 8
    static let showingWidth: CGFloat = 44
    static let waitingWidth: CGFloat = 24
    static let dotSize: CGFloat = 12
    static let dotTarget: CGFloat = 24
    static let spacing: CGFloat = 4
    static let chipIconSize: CGFloat = 36
    static let expandedSize = CGSize(width: 440, height: 104)
    private static let sidePadding: CGFloat = 8

    struct Segment: Equatable {
        var id: WindowID
        var isShowing: Bool
        var width: CGFloat
    }

    /// One segment per window, each keeping its place; only the long one moves. `windows` is the tile's
    /// list, with the showing window first.
    static func segments(of windows: [WindowID]) -> [Segment] {
        Tile(windows: windows).barOrder.map { id in
            let isShowing = id == windows.first
            return Segment(id: id, isShowing: isShowing, width: isShowing ? showingWidth : waitingWidth)
        }
    }

    static func collapsedSize(count: Int, isActive: Bool) -> CGSize {
        let others = CGFloat(max(count - 1, 0))
        let content =
            isActive
            ? showingWidth + others * (waitingWidth + spacing)
            : dotTarget + others * (dotTarget + spacing)
        return CGSize(width: content + sidePadding * 2, height: hitHeight)
    }
}

/// The handle above a tile: segments for the active tile, dots for inactive stacks, and the bar of
/// quick actions and window chips when the pointer rests on it.
final class GripPanel: NSPanel {
    /// This panel never becomes key, so the first click has to count.
    private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }


    private let model = GripModel()
    private var anchor: CGRect = .zero
    private var gap: CGFloat = 8

    init(controller: AppController) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // By default macOS sends clicks on transparent pixels to the window below, which would leave
        // only the drawn segments clickable. Setting this explicitly makes the whole panel catch them.
        ignoresMouseEvents = false
        contentView = FirstClickHostingView(rootView: GripView(model: model, controller: controller))
        model.onExpansionChange = { [weak self] _ in self?.reposition() }
    }

    func show(
        windows: [WindowID], isActive: Bool, above frame: CGRect, gap: CGFloat, style: AppSettings.StackBar
    ) {
        model.style = style
        model.windows = windows
        model.isActive = isActive
        // Only the active tile has the bar of actions.
        if !isActive { model.expanded = false }
        anchor = frame
        self.gap = gap
        reposition()
        orderFrontRegardless()
    }

    private func reposition() {
        let size: CGSize
        if model.expanded {
            size = GripMetrics.expandedSize
        } else {
            size = GripMetrics.collapsedSize(count: model.windows.count, isActive: model.isActive)
        }
        // The visible bar stays centered in the gap above the window; only its click area reaches past.
        let top = anchor.minY - gap / 2 - GripMetrics.hitHeight / 2
        let rect = CGRect(x: anchor.midX - size.width / 2, y: top, width: size.width, height: size.height)
        setFrame(Displays.toAppKit(rect), display: true)
    }
}

private struct GripView: View {
    @Bindable var model: GripModel
    let controller: AppController
    @State private var pendingExpansion: Task<Void, Never>?

    var body: some View {
        Group {
            if model.expanded {
                HoverBar(windows: model.windows, color: barColor, controller: controller)
            } else {
                segments
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover(perform: hoverChanged)
    }

    private var barColor: Color { Color(nsColor: model.style.resolvedColor) }

    private var segments: some View {
        HStack(spacing: GripMetrics.spacing) {
            ForEach(GripMetrics.segments(of: model.windows), id: \.id) { segment in
                Button {
                    controller.showWindow(segment.id)
                } label: {
                    if model.isActive {
                        Capsule()
                            .fill(barColor.opacity(segment.isShowing ? 1 : 0.6))
                            .frame(
                                width: segment.width,
                                height: GripMetrics.barHeight
                            )
                            .frame(height: GripMetrics.hitHeight)
                            .contentShape(Rectangle())
                    } else {
                        Circle()
                            .fill(barColor.opacity(segment.isShowing ? 1 : 0.55))
                            .frame(width: GripMetrics.dotSize, height: GripMetrics.dotSize)
                            .frame(width: GripMetrics.dotTarget, height: GripMetrics.hitHeight)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
    }

    private func hoverChanged(_ hovering: Bool) {
        pendingExpansion?.cancel()
        pendingExpansion = Task {
            try? await Task.sleep(for: hovering ? model.style.resolvedDelay : .milliseconds(400))
            // Replacing the segments mid-click would lose the click.
            guard !Task.isCancelled, model.isActive || !hovering, NSEvent.pressedMouseButtons == 0 else { return }
            if model.expanded != hovering {
                model.expanded = hovering
                model.onExpansionChange?(hovering)
            }
        }
    }
}

private struct HoverBar: View {
    let windows: [WindowID]
    let color: Color
    let controller: AppController

    private var active: WindowID? { windows.first }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if let active {
                    action("star", "Make primary") { controller.makePrimaryWindow(active) }
                    action("arrow.up.left.and.arrow.down.right", "Focus") { controller.toggleZoomWindow(active) }
                    action("pin", "Float") { controller.toggleFloatWindow(active) }
                    moveControl(active)
                }
            }
            HStack(spacing: 4) {
                action("chevron.left", "Previous window") { cycle(forward: false) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Tile(windows: windows).barOrder, id: \.self) { id in
                            WindowChip(id: id, isShowing: id == active, color: color, controller: controller)
                        }
                    }
                }
                action("chevron.right", "Next window") { cycle(forward: true) }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func cycle(forward: Bool) {
        guard let active, let next = controller.state.cycleStack(of: active, forward: forward) else { return }
        controller.showWindow(next)
    }

    @ViewBuilder
    private func moveControl(_ id: WindowID) -> some View {
        let screens = controller.orderedScreens()
        if screens.count == 2 {
            action("display.2", "Next screen") { controller.moveToNextScreen(id) }
        } else if screens.count > 2 {
            Menu {
                ForEach(screens, id: \.key) { screen in
                    Button(screen.name) { controller.moveWindow(id, to: screen.key) }
                }
            } label: {
                Label("Move to", systemImage: "display.2").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(Text("Move to"))
        }
    }

    private func action(
        _ symbol: String, _ title: LocalizedStringKey, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .help(Text(title))
    }
}

private struct WindowChip: View {
    let id: WindowID
    let isShowing: Bool
    let color: Color
    let controller: AppController
    @State private var isHovering = false

    private var record: WindowRecord? { controller.ax.record(id) }

    var body: some View {
        HStack(spacing: 2) {
            if let pid = record?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable()
                    .frame(width: GripMetrics.chipIconSize, height: GripMetrics.chipIconSize)
            }
            if isHovering {
                Button {
                    controller.closeWindow(id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .help(Text("Close window"))
            }
        }
        .padding(4)
        .background(
            isShowing ? color.opacity(0.35) : Color.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(MiddleClickCatcher { controller.closeWindow(id) })
        .onHover { isHovering = $0 }
        .onTapGesture { controller.showWindow(id) }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { _ in controller.chipDragHover(id: id) }
                .onEnded { _ in controller.dropChip(id: id) }
        )
    }
}

/// SwiftUI has no middle-click gesture.
private struct MiddleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSEvent.pressedMouseButtons & 0b100 != 0 ? super.hitTest(point) : nil
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 { action?() }
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }
}
