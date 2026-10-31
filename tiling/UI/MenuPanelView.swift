import AppKit
import SwiftUI

extension LayoutKind {
    var title: LocalizedStringKey {
        switch self {
        case .grid: "Grid"
        case .columns: "Columns"
        case .rows: "Rows"
        case .side: "Side"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .columns: "rectangle.split.3x1"
        case .rows: "rectangle.split.1x2"
        case .side: "sidebar.right"
        }
    }
}

struct MenuBarIcon: View {
    let controller: AppController

    var body: some View {
        Image(nsImage: Self.image(filled: controller.status.isTiling, mark: controller.hasCleanSpace))
    }

    private static func image(filled: Bool, mark: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = NSImage(
            systemSymbolName: filled ? "rectangle.split.2x2.fill" : "rectangle.split.2x2",
            accessibilityDescription: "Tiling")?.withSymbolConfiguration(configuration)
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            if let symbol {
                symbol.draw(in: NSRect(
                    x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2,
                    width: symbol.size.width, height: symbol.size.height))
            }
            if mark {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 17, y: 12, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuPanelView: View {
    @Bindable var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow
            cards
            if let key = controller.pointerKey() {
                PanelPreview(controller: controller, key: key)
                windowsOnThisScreen(key)
            }
            Divider()
            quickSwitches
            modes
            frontAppToggle
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var statusRow: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.subheadline.weight(.medium))
            Spacer()
            Toggle("Automatic tiling", isOn: $controller.settings.tilingEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .tiling: .green
        case .stageManager, .waitingForSetup: .orange
        case .off: .gray
        case .needsAccess: .red
        }
    }

    private var statusText: String {
        switch controller.status {
        case .tiling(1, false): String(localized: "Tiling 1 window.")
        case .tiling(1, true): String(localized: "Focus mode · 1 window.")
        case .tiling(let count, false): String(localized: "Tiling \(count) windows.")
        case .tiling(let count, true): String(localized: "Focus mode · \(count) windows.")
        case .stageManager: String(localized: "Paused while Stage Manager is on.")
        case .waitingForSetup: String(localized: "Waiting for setup to finish.")
        case .off: String(localized: "Automatic tiling is off.")
        case .needsAccess: String(localized: "Needs Accessibility access.")
        }
    }

    @ViewBuilder
    private var cards: some View {
        if controller.status == .needsAccess {
            card("Tiling needs Accessibility access to arrange windows", button: "Grant Access") {
                AXWindowSystem.requestTrust()
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if controller.status == .waitingForSetup {
            card("Finish the tour to start tiling.", button: "Continue") { TourWindow.show(controller: controller) }
        }
        if controller.secureInputOn {
            card("Another app turned on Secure Input. Shortcuts are paused until it ends.")
        }
        if controller.hotKeysFailed {
            card("macOS couldn't set up Tiling's keyboard shortcuts. Quit and reopen Tiling.")
        }
        if let error = controller.configError {
            card("\(error) has an error. Keeping the last good values.")
        }
    }

    private func card(
        _ text: LocalizedStringKey, button: LocalizedStringKey? = nil, action: @escaping () -> Void = {}
    ) -> some View {
        HStack {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button { Button(button, action: action).controlSize(.small) }
        }
        .padding(8)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private func windowsOnThisScreen(_ key: WorkspaceKey) -> some View {
        let workspace = controller.state.workspaces[key]
        let context = controller.context()
        let area = controller.state.area(of: key, context: context) ?? .zero
        let vertical = Orientation(area: area) == .vertical
        let kind = workspace.map { controller.state.resolvedKind($0, area: area, policy: context.policy) }
            ?? controller.settings.layout ?? .grid
        let maxCount = controller.maxCount(kind: kind, on: key)
        let selected = min(workspace?.count ?? controller.settings.windowsPerScreen, maxCount)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Windows on this screen").font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(LayoutKind.allCases, id: \.self) { option in
                    Button {
                        controller.setKind(option, on: key)
                    } label: {
                        Image(systemName: option.symbol).frame(width: 26, height: 20)
                    }
                    .buttonStyle(.bordered)
                    .tint(option == kind ? .orange : nil)
                    .disabled(vertical && option == .columns)
                    .help(Text(option.title))
                }
                Spacer()
                ForEach(1...(maxCount == 5 ? 5 : 4), id: \.self) { count in
                    Button("\(count)") { controller.setCount(count, on: key) }
                        .buttonStyle(.bordered)
                        .tint(count == selected ? .orange : nil)
                        .disabled(count > maxCount)
                }
            }
            if vertical {
                Text("Columns isn't available on a vertical screen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if maxCount < 4 {
                Text("This screen is too small for more than \(maxCount) windows in this layout.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var quickSwitches: some View {
        HStack {
            Button("Retile") { controller.retile() }
            Toggle("Borders", isOn: bordersBinding).toggleStyle(.button)
            Toggle("Hover focus", isOn: $controller.settings.hoverFocus).toggleStyle(.button)
        }
        .controlSize(.small)
        .disabled(!controller.isOperating)
    }

    private var bordersBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.highlight.style != .none },
            set: { controller.settings.highlight.style = $0 ? .activeBorder : .none })
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "No peek mode",
                isOn: Binding(get: { controller.noPeekOn }, set: { _ in controller.toggleNoPeek() }))
            if controller.noPeekOn {
                Slider(value: $controller.settings.noPeek.dim, in: 10...90) { Text("Dim amount") }
                    .controlSize(.small)
            }
            Toggle(
                "Clean Space",
                isOn: Binding(
                    get: {
                        controller.pointerKey().flatMap { controller.state.workspaces[$0]?.cleanSet } != nil
                    }, set: { _ in controller.toggleCleanSpace(on: controller.pointerKey()) }))
        }
        .disabled(!controller.isOperating)
    }

    @ViewBuilder
    private var frontAppToggle: some View {
        if let app = controller.frontApp, let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier {
            Toggle(
                String(localized: "Tile \(app.localizedName ?? bundleID)"),
                isOn: Binding(
                    get: { !controller.rules.excluded.contains(bundleID) },
                    set: { _ in controller.toggleTile(for: bundleID) }))
        }
    }

    /// Warns when shortcuts could not all be registered, and reads Off when disabled.
    @ViewBuilder
    private var keyboardLabel: some View {
        if !controller.shortcuts.enabled {
            Text("Keyboard shortcuts: Off")
        } else if controller.hotKeysFailed {
            Label("Keyboard shortcuts", systemImage: "exclamationmark.triangle")
        } else {
            Text("Keyboard shortcuts")
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Text("Settings") }
                .keyboardShortcut(",")
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            Spacer()
            SettingsLink { keyboardLabel }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        controller.settingsTab = .keyboard
                        NSApp.activate()
                    })
            Spacer()
            Button("Quit Tiling") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

private struct PanelPreview: View {
    let controller: AppController
    let key: WorkspaceKey

    var body: some View {
        let revision = controller.revision
        let context = controller.context()
        let area = controller.state.area(of: key, context: context) ?? CGRect(x: 0, y: 0, width: 16, height: 10)
        let workspace = controller.state.workspaces[key]
        let frames = controller.state.slotFrames(on: key, context: context)
        let scale = 292 / max(area.width, 1)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                ForEach(Array((workspace?.tiles ?? []).enumerated()), id: \.offset) { index, tile in
                    if let frame = frames[safe: index], let shown = tile.windows.first {
                        miniature(shown, tile: tile, zoomed: workspace?.zoomed)
                            .frame(width: frame.width * scale, height: frame.height * scale)
                            .offset(x: (frame.minX - area.minX) * scale, y: (frame.minY - area.minY) * scale)
                    }
                }
            }
            .frame(width: 292, height: area.height * scale)
            .id(revision)
            if controller.state.hasCustomSizes(on: key) {
                Button("Reset sizes") { controller.resetSizes(on: key) }.controlSize(.small)
            }
        }
    }

    private func miniature(_ id: WindowID, tile: Tile, zoomed: WindowID?) -> some View {
        let isActive = tile.windows.contains { $0 == controller.state.focused }
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(zoomed != nil && zoomed != id ? 0.05 : 0.15))
            if let pid = controller.ax.record(id)?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    .opacity(zoomed != nil && zoomed != id ? 0.4 : 1)
            }
            if zoomed == id {
                Text("Focus").font(.caption2.weight(.semibold)).offset(y: 18)
            }
            if isActive {
                RoundedRectangle(cornerRadius: 4).stroke(Color.orange, lineWidth: 1.5)
            }
        }
    }
}
