import AppKit
import SwiftUI

enum TourWindow {
    private static var window: NSWindow?

    static func show(controller: AppController) {
        // A closed tour starts over; one still open keeps its place.
        if window?.isVisible != true {
            let created = NSWindow(contentViewController: NSHostingController(rootView: TourView(controller: controller)))
            created.title = String(localized: "Welcome to Terrazzo")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() {
        window?.close()
    }
}

/// Nothing moves until the last step.
private struct TourView: View {
    @Bindable var controller: AppController
    @State private var step = 0

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 20) {
            Group {
                switch step {
                case 0: welcome
                case 1: permission
                case 2: makeItYours
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if step > 0, step < lastStep {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step == lastStep {
                    Button("Tidy My Workspace") {
                        controller.finishSetup()
                        TourWindow.close()
                    }
                    .keyboardShortcut(.defaultAction)
                } else if step > 0 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(step == 1 && !controller.isTrusted)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 440)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: AppIconRenderer.image(for: controller.settings.iconStyle))
                .resizable().frame(width: 96, height: 96)
            Text("Open a window and Terrazzo gives it a place.").font(.title2.weight(.semibold))
            Text("When a window closes, the others fill the space. When the screen is full, new windows stack in the tile you're using.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Use Terrazzo") { step = controller.isTrusted ? 2 : 1 }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var permission: some View {
        VStack(spacing: 16) {
            Image(systemName: controller.isTrusted ? "checkmark.circle.fill" : "lock.shield")
                .font(.system(size: 48)).foregroundStyle(controller.isTrusted ? .green : .orange)
            Text("Allow Accessibility access").font(.title2.weight(.semibold))
            Text("Terrazzo uses it only to read and set the position and size of windows. It takes no screenshots, reads no document contents and saves no window titles.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if !controller.isTrusted {
                Button("Grant Access") {
                    AXWindowSystem.requestTrust()
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Toggle("Open at login", isOn: $controller.settings.openAtLogin)
        }
    }

    private var makeItYours: some View {
        Form {
            Picker("Layout", selection: $controller.settings.layout) {
                Text("Automatic").tag(LayoutKind?.none)
                ForEach(LayoutKind.allCases, id: \.self) { Text($0.title).tag(LayoutKind?.some($0)) }
            }
            Stepper(
                "Windows per screen: \(controller.settings.windowsPerScreen)",
                value: $controller.settings.windowsPerScreen, in: 1...5)
            Picker("Active window highlight", selection: $controller.settings.highlight.style) {
                Text("None").tag(HighlightStyle.none)
                Text("Active border").tag(HighlightStyle.activeBorder)
                Text("All borders").tag(HighlightStyle.allBorders)
                Text("Glow").tag(HighlightStyle.glow)
            }
            Picker("When a screen is full", selection: $controller.settings.whenFull) {
                Text("Stack on top").tag(FullScreenBehavior.stack)
                Text("Float in the middle").tag(FullScreenBehavior.floatInMiddle)
            }
        }
        .formStyle(.grouped)
    }

    private var ready: some View {
        VStack(spacing: 12) {
            Text("Ready").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                shortcutLine("⌃ ← → ↑ ↓", "Move focus between windows")
                shortcutLine("⌃⇧ ← → ↑ ↓", "Swap windows")
                shortcutLine("⌃ 1–9", "Switch workspace")
                shortcutLine("⌃⌥↩", "Make the active window primary")
                shortcutLine("⌃F", "Focus mode")
                shortcutLine("⌃⌥D", "No peek mode")
                shortcutLine("⌃⌥P", "Clean Space")
                shortcutLine("⌃⇥", "Tab View")
            }
            Text("Your settings live in \(ConfigDirectory.url().path)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func shortcutLine(_ keys: String, _ title: LocalizedStringKey) -> some View {
        HStack {
            Text(keys).monospaced().frame(width: 120, alignment: .leading)
            Text(title)
        }
    }
}

enum AppIconRenderer {
    private static func colors(_ style: IconStyle) -> (NSColor, NSColor, NSColor) {
        func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
        switch style {
        case .terrazzo, .washi: return (color(0.96, 0.93, 0.86), color(0.87, 0.82, 0.72), color(0.24, 0.20, 0.17))
        case .lantern: return (color(0.98, 0.72, 0.30), color(0.87, 0.36, 0.14), color(1, 0.96, 0.86))
        case .indigo: return (color(0.20, 0.25, 0.50), color(0.09, 0.11, 0.28), color(0.86, 0.89, 1))
        case .sunset: return (color(0.98, 0.56, 0.42), color(0.55, 0.24, 0.55), color(1, 0.94, 0.88))
        case .torii: return (color(0.85, 0.20, 0.16), color(0.55, 0.09, 0.08), color(1, 0.95, 0.90))
        case .glass: return (color(0.80, 0.90, 0.96), color(0.56, 0.72, 0.84), color(1, 1, 1))
        case .focus: return (color(0.12, 0.12, 0.14), color(0.03, 0.03, 0.04), color(1, 0.58, 0))
        }
    }

    static func image(for style: IconStyle) -> NSImage {
        if style.usesBundledIcon, let bundled = NSImage(named: NSImage.applicationIconName) { return bundled }
        let (top, bottom, panes) = colors(style)
        let side: CGFloat = 512
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 96, yRadius: 96)
            NSGradient(starting: top, ending: bottom)?.draw(in: body, angle: -90)
            panes.setFill()
            let inner = rect.insetBy(dx: 120, dy: 120)
            let gap: CGFloat = 20
            let half = (inner.width - gap) / 2
            NSBezierPath(
                roundedRect: NSRect(x: inner.minX, y: inner.minY, width: half, height: inner.height),
                xRadius: 16, yRadius: 16
            ).fill()
            for y in [inner.minY, inner.minY + half + gap] {
                NSBezierPath(
                    roundedRect: NSRect(x: inner.minX + half + gap, y: y, width: half, height: half),
                    xRadius: 16, yRadius: 16
                ).fill()
            }
            return true
        }
    }
}
