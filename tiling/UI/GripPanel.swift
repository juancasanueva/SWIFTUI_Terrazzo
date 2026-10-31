import AppKit
import SwiftUI

@Observable
final class GripModel {
    var windows: [WindowID] = []
    var isActive = false
    var expanded = false
    var onExpansionChange: ((Bool) -> Void)?
}

/// The handle above a tile: segments for the active tile, dots for inactive stacks, and the bar of
/// quick actions and window chips when the pointer rests on it.
final class GripPanel: NSPanel {
    private static let collapsedHeight: CGFloat = 12
    private static let expandedSize = CGSize(width: 440, height: 84)

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
        contentView = NSHostingView(rootView: GripView(model: model, controller: controller))
        model.onExpansionChange = { [weak self] _ in self?.reposition() }
    }

    func show(windows: [WindowID], isActive: Bool, above frame: CGRect, gap: CGFloat) {
        model.windows = windows
        model.isActive = isActive
        anchor = frame
        self.gap = gap
        reposition()
        orderFrontRegardless()
    }

    private func reposition() {
        let size: CGSize
        if model.expanded {
            size = Self.expandedSize
        } else {
            let unit: CGFloat = model.isActive ? 18 : 12
            size = CGSize(width: max(CGFloat(model.windows.count) * unit + 24, 48), height: Self.collapsedHeight)
        }
        let top = anchor.minY - gap / 2 - Self.collapsedHeight / 2
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
                HoverBar(windows: model.windows, controller: controller)
            } else {
                segments
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover(perform: hoverChanged)
    }

    private var segments: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.windows.enumerated()), id: \.element) { index, id in
                Button {
                    controller.showWindow(id)
                } label: {
                    if model.isActive {
                        Capsule()
                            .fill(Color.orange.opacity(index == 0 ? 1 : 0.45))
                            .frame(width: index == 0 ? 24 : 10, height: 4)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    } else {
                        Circle()
                            .fill(Color.orange.opacity(index == 0 ? 1 : 0.55))
                            .frame(width: 6, height: 6)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        pendingExpansion?.cancel()
        pendingExpansion = Task {
            try? await Task.sleep(for: .milliseconds(hovering ? 250 : 400))
            guard !Task.isCancelled, model.isActive || !hovering else { return }
            if model.expanded != hovering {
                model.expanded = hovering
                model.onExpansionChange?(hovering)
            }
        }
    }
}

private struct HoverBar: View {
    let windows: [WindowID]
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
                        ForEach(windows, id: \.self) { id in
                            WindowChip(id: id, isShowing: id == active, controller: controller)
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
    let controller: AppController
    @State private var isHovering = false

    private var record: WindowRecord? { controller.ax.record(id) }

    var body: some View {
        HStack(spacing: 2) {
            if let pid = record?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            if isHovering {
                Button {
                    controller.closeWindow(id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .help(Text("Close window"))
            }
        }
        .padding(4)
        .background(
            isShowing ? Color.orange.opacity(0.35) : Color.primary.opacity(0.08),
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
