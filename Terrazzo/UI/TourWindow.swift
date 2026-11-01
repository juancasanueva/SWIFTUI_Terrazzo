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
            Image(nsImage: NSApp.applicationIconImage)
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
