import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var controller: AppController

    var body: some View {
        TabView(selection: $controller.settingsTab) {
            GeneralSettings(controller: controller).tabItem { Label("General", systemImage: "gearshape") }
                .tag(AppController.SettingsTab.general)
            LayoutSettings(controller: controller).tabItem { Label("Layout", systemImage: "square.grid.2x2") }
                .tag(AppController.SettingsTab.layout)
            HighlightSettings(controller: controller).tabItem { Label("Highlight", systemImage: "sparkles") }
                .tag(AppController.SettingsTab.highlight)
            KeyboardSettings(controller: controller).tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(AppController.SettingsTab.keyboard)
            AppsSettings(controller: controller).tabItem { Label("Apps", systemImage: "app.badge") }
                .tag(AppController.SettingsTab.apps)
            AboutSettings(controller: controller).tabItem { Label("About", systemImage: "info.circle") }
                .tag(AppController.SettingsTab.about)
        }
        .frame(width: 560, height: 560)
        .onAppear { NSApp.activate() }
    }
}

private struct GeneralSettings: View {
    @Bindable var controller: AppController
    @State private var needsRestart = false

    private static let languages: [(code: String?, name: String)] = [
        (nil, String(localized: "Match the Mac")), ("en", "English"), ("es", "Español"), ("ja", "日本語"),
        ("ko", "한국어"), ("zh-Hans", "简体中文"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $controller.settings.language) {
                    ForEach(Self.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                .onChange(of: controller.settings.language) { needsRestart = true }
                if needsRestart {
                    Button("Restart Now", action: restart)
                }
                Picker("Appearance", selection: $controller.settings.appearance) {
                    Text("Match the Mac").tag(AppearanceChoice.system)
                    Text("Light").tag(AppearanceChoice.light)
                    Text("Dark").tag(AppearanceChoice.dark)
                }
                Toggle("Open at login", isOn: $controller.settings.openAtLogin)
                Picker("Clean Space background", selection: $controller.settings.cleanBackground) {
                    Text("Graphite").tag(CleanBackground.graphite)
                    Text("Mist").tag(CleanBackground.mist)
                    Text("Stone").tag(CleanBackground.stone)
                }
            }
            Section {
                LabeledContent("Permission") {
                    HStack {
                        Text(controller.isTrusted ? "Accessibility allowed" : "Accessibility needed")
                        if !controller.isTrusted {
                            Button("Grant Access") { AXWindowSystem.requestTrust() }
                        }
                    }
                }
                Button("Open Tour") { TourWindow.show(controller: controller) }
            }
        }
        .formStyle(.grouped)
    }

    private func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

private struct LayoutSettings: View {
    @Bindable var controller: AppController
    @State private var edgeScope = "all"

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: $controller.settings.layout) {
                    Text("Automatic").tag(LayoutKind?.none)
                    ForEach(LayoutKind.allCases, id: \.self) { Text($0.title).tag(LayoutKind?.some($0)) }
                }
                Picker("Main window size", selection: $controller.settings.mainSize) {
                    Text("Half").tag(MainSize.half)
                    Text("60%").tag(MainSize.sixty)
                    Text("Two-thirds").tag(MainSize.twoThirds)
                }
                Stepper(
                    "Windows per screen: \(controller.settings.windowsPerScreen)",
                    value: $controller.settings.windowsPerScreen, in: 1...5)
                Picker("When a screen is full", selection: $controller.settings.whenFull) {
                    Text("Stack on top").tag(FullScreenBehavior.stack)
                    Text("Float in the middle").tag(FullScreenBehavior.floatInMiddle)
                }
                Picker("Moving into a full screen", selection: $controller.settings.movingIntoFull) {
                    Text("Swap").tag(MoveIntoFullBehavior.swap)
                    Text("Stack on top").tag(MoveIntoFullBehavior.stackOnTop)
                }
                LabeledContent("Resize step") {
                    HStack {
                        Slider(value: $controller.settings.resizeStep, in: AppSettings.resizeStepRange, step: 0.5)
                        Text(verbatim: String(format: "%g%%", controller.settings.resizeStep)).monospacedDigit()
                    }
                }
                LabeledContent("Spacing") {
                    HStack {
                        Slider(value: $controller.settings.gap, in: 0...32, step: 1)
                        Text("\(Int(controller.settings.gap)) pt").monospacedDigit()
                    }
                }
            }
            Section("Workspace displays") {
                WorkspaceDisplayHeader()
                let externalNames = Displays.current().filter { !$0.isBuiltIn }.map(\.name)
                ForEach(Array(VirtualWorkspaces.numbers), id: \.self) { number in
                    WorkspaceDisplayRow(
                        number: number, preference: $controller.settings.workspaceDisplays[String(number)],
                        externalNames: externalNames)
                }
            }
            Section("Screen edges") {
                Picker("Apply to", selection: $edgeScope) {
                    Text("All screens").tag("all")
                    ForEach(Displays.current(), id: \.uuid) { Text($0.name).tag($0.uuid) }
                }
                edgeSlider("Top", \.top)
                edgeSlider("Left", \.left)
                edgeSlider("Bottom", \.bottom)
                edgeSlider("Right", \.right)
            }
        }
        .formStyle(.grouped)
    }

    private func edgeSlider(_ title: LocalizedStringKey, _ edge: WritableKeyPath<ScreenEdges, CGFloat>) -> some View {
        let binding = Binding<Double>(
            get: {
                let edges = edgeScope == "all"
                    ? controller.settings.screenEdges
                    : controller.settings.screenEdgesByDisplay[edgeScope] ?? controller.settings.screenEdges
                return Double(edges[keyPath: edge])
            },
            set: { value in
                if edgeScope == "all" {
                    controller.settings.screenEdges[keyPath: edge] = CGFloat(value)
                } else {
                    var edges = controller.settings.screenEdgesByDisplay[edgeScope] ?? controller.settings.screenEdges
                    edges[keyPath: edge] = CGFloat(value)
                    controller.settings.screenEdgesByDisplay[edgeScope] = edges
                }
            })
        return LabeledContent(title) {
            HStack {
                Slider(value: binding, in: 0...200, step: 2)
                Text("\(Int(binding.wrappedValue)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// Titles for the two columns of `WorkspaceDisplayRow`.
struct WorkspaceDisplayHeader: View {
    var body: some View {
        HStack {
            WorkspaceDisplayRow.label(VirtualWorkspaces.numbers.upperBound).hidden()
            Group {
                Text("Display")
                Text("If not connected")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.leading, WorkspaceDisplayRow.menuInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// One workspace on one row: the display it shows on, then what to use while that display is away.
struct WorkspaceDisplayRow: View {
    /// How far a menu's text sits from the menu's leading edge, so the column titles line up with it.
    static let menuInset: CGFloat = 12

    let number: Int
    @Binding var preference: DisplayPreference?
    /// The connected displays other than the built-in one.
    let externalNames: [String]

    private var current: DisplayPreference { preference ?? DisplayPreference([]) }

    var body: some View {
        HStack {
            Self.label(number).accessibilityHidden(true)
            Picker(String(localized: "Workspace \(number)"), selection: primary) {
                Text("Any display").tag("")
                ForEach(displayChoices, id: \.self) { Text(Self.title($0)).tag($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Kept in place while unused, so the columns don't move as displays are chosen.
            Picker("If not connected", selection: fallbacks) {
                Text("Any display").tag([String]())
                ForEach(fallbackChoices, id: \.self) { choice in
                    Text(choice.map(Self.title).joined(separator: ", ")).tag(choice)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(current.primary.isEmpty ? 0 : 1)
            .disabled(current.primary.isEmpty)
            .accessibilityHidden(current.primary.isEmpty)
        }
        .labelsHidden()
    }

    /// Every number takes the same width, so the columns line up down the list.
    static func label(_ number: Int) -> some View {
        Text("Workspace \(number)").monospacedDigit()
    }

    private var primary: Binding<String> {
        Binding(get: { current.primary }, set: { preference = current.choosing(primary: $0) })
    }

    private var fallbacks: Binding<[String]> {
        Binding(get: { current.fallbacks }, set: { preference = current.choosing(fallbacks: $0) })
    }

    /// The built-in display goes by role, so the choice holds in any language; the others go by name.
    private var displayChoices: [String] {
        var choices = [DisplayPreference.builtIn] + externalNames
        // A pin can be part of a name, or name a monitor that isn't connected: keep it selectable.
        if !current.primary.isEmpty, !choices.contains(current.primary) { choices.append(current.primary) }
        return choices
    }

    private var fallbackChoices: [[String]] {
        var choices = [DisplayPreference.builtIn, DisplayPreference.external]
            .filter { $0 != current.primary }
            .map { [$0] }
        // A longer list written in the config by hand stays selectable.
        if !current.fallbacks.isEmpty, !choices.contains(current.fallbacks) { choices.append(current.fallbacks) }
        return choices
    }

    private static func title(_ candidate: String) -> String {
        switch candidate {
        case DisplayPreference.builtIn: String(localized: "Built-in display")
        case DisplayPreference.external: String(localized: "Any external display")
        default: candidate
        }
    }
}

private struct HighlightSettings: View {
    @Bindable var controller: AppController

    var body: some View {
        Form {
            Section {
                Picker("Active window highlight", selection: $controller.settings.highlight.style) {
                    Text("None").tag(HighlightStyle.none)
                    Text("Active border").tag(HighlightStyle.activeBorder)
                    Text("All borders").tag(HighlightStyle.allBorders)
                    Text("Glow").tag(HighlightStyle.glow)
                }
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { Color(nsColor: NSColor(hex: controller.settings.highlight.color) ?? .systemOrange) },
                        set: { controller.settings.highlight.color = NSColor($0).hexString }),
                    supportsOpacity: false)
                LabeledContent("Width") {
                    Slider(value: $controller.settings.highlight.width, in: 1...8, step: 1)
                }
                LabeledContent("Corner radius") {
                    HStack {
                        Slider(value: $controller.settings.highlight.cornerRadius, in: 0...40, step: 1)
                        Text("\(Int(controller.settings.highlight.cornerRadius)) pt").monospacedDigit()
                    }
                }
                Toggle("Hover focus", isOn: $controller.settings.hoverFocus)
                Toggle("Follow a window moved to another workspace", isOn: $controller.settings.followMovedWindow)
                Toggle("Move the pointer to the focused window", isOn: $controller.settings.movePointer.onWindowFocus)
                Toggle("Move the pointer to the focused monitor", isOn: $controller.settings.movePointer.onMonitorChange)
            }
            Section("Stacked windows") {
                ColorPicker(
                    "Bar color",
                    selection: Binding(
                        get: { Color(nsColor: controller.settings.stackBar.resolvedColor) },
                        set: { controller.settings.stackBar.color = NSColor($0).hexString }),
                    supportsOpacity: false)
                LabeledContent("Wait before showing the icons") {
                    HStack {
                        Slider(
                            value: $controller.settings.stackBar.hoverDelay,
                            in: 0...AppSettings.StackBar.maximumDelay, step: 0.1)
                        Text(verbatim: String(format: "%.1f s", controller.settings.stackBar.hoverDelay))
                            .monospacedDigit()
                    }
                }
            }
            Section {
                Toggle(
                    "No peek mode",
                    isOn: Binding(get: { controller.noPeekOn }, set: { _ in controller.toggleNoPeek() }))
                LabeledContent("Dim amount") {
                    HStack {
                        Slider(value: $controller.settings.noPeek.dim, in: 10...90, step: 5)
                        Text("\(Int(controller.settings.noPeek.dim))%").monospacedDigit()
                    }
                }
                Toggle("Blur other windows", isOn: $controller.settings.noPeek.blur)
            }
        }
        .formStyle(.grouped)
    }
}

extension ShortcutAction {
    var title: LocalizedStringKey {
        if let number = workspaceNumber { return "Switch to workspace \(number)" }
        if let number = moveWorkspaceNumber { return "Move window to workspace \(number)" }
        return switch self {
        case .resizeLeft: "Move a window edge left"
        case .resizeRight: "Move a window edge right"
        case .resizeUp: "Move a window edge up"
        case .resizeDown: "Move a window edge down"
        case .focusLeft: "Focus the window on the left"
        case .focusRight: "Focus the window on the right"
        case .focusUp: "Focus the window above"
        case .focusDown: "Focus the window below"
        case .swapLeft: "Swap with the window on the left"
        case .swapRight: "Swap with the window on the right"
        case .swapUp: "Swap with the window above"
        case .swapDown: "Swap with the window below"
        case .makePrimary: "Make the active window primary"
        case .nextWindow: "Activate the next window"
        case .previousWindow: "Activate the previous window"
        case .nextInTile: "Show the next window in this tile"
        case .previousInTile: "Show the previous window in this tile"
        case .tabView: "Tab View"
        case .tabViewBackward: "Tab View, moving backwards"
        case .bigger: "Make the active window bigger"
        case .smaller: "Make the active window smaller"
        case .resetSizes: "Reset window sizes on this screen"
        case .float: "Float the active window, or tile it again"
        case .alwaysFloat: "Always float windows like the active one"
        case .focus: "Focus mode"
        case .noPeek: "No peek mode"
        case .cleanSpace: "Clean Space"
        case .retile: "Retile"
        case .tile1: "Tile 1 window on this screen"
        case .tile2: "Tile up to 2 windows on this screen"
        case .tile3: "Tile up to 3 windows on this screen"
        case .tile4: "Tile up to 4 windows on this screen"
        case .tile5: "Tile up to 5 windows"
        default: ""
        }
    }
}

private struct KeyboardSettings: View {
    @Bindable var controller: AppController
    @State private var recording: ShortcutAction?
    @State private var candidate: KeyCombo?
    @State private var monitor: Any?

    private var system: Set<KeyCombo> { HotKeyCenter.systemShortcuts() }

    var body: some View {
        Form {
            Section {
                Toggle("Keyboard shortcuts", isOn: $controller.shortcuts.enabled)
                Picker("Shortcut prefix", selection: $controller.shortcuts.prefix) {
                    ForEach(ShortcutPrefix.allCases, id: \.self) { Text($0.symbols).tag($0) }
                }
                unusable
                Button("Reset All") { controller.shortcuts.resetAll() }
            }
            if let candidate, let recording { conflictSection(candidate, recording) }
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in row(action) }
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: stopRecording)
    }

    @ViewBuilder
    private var unusable: some View {
        let taken = ShortcutAction.allCases.filter {
            controller.shortcuts.combo(for: $0).map(system.contains) ?? false
        }
        if !taken.isEmpty {
            Text("macOS uses some of these keys: \(taken.compactMap { controller.shortcuts.combo(for: $0)?.symbols }.joined(separator: " "))")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func row(_ action: ShortcutAction) -> some View {
        let combo = controller.shortcuts.combo(for: action)
        let changed = controller.shortcuts.bindings[action.rawValue] != nil
        return LabeledContent(action.title) {
            HStack {
                if changed {
                    Button {
                        controller.shortcuts.reset(action)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                }
                Button(recording == action ? String(localized: "Press keys…") : combo?.symbols ?? String(localized: "Off")) {
                    startRecording(action)
                }
                .monospaced()
            }
        }
    }

    @ViewBuilder
    private func conflictSection(_ combo: KeyCombo, _ action: ShortcutAction) -> some View {
        let conflicts = controller.shortcuts.conflicts(for: combo, action: action, system: system)
        Section {
            Text("\(controller.shortcuts.symbols(recording: combo, for: action)) is already in use:").font(.callout)
            ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                switch conflict {
                case .system: Text("macOS").font(.caption)
                case .shortcut(let other): Text(other.title).font(.caption)
                }
            }
            // The window-count shortcuts keep their number keys, so a free key is no use to them.
            if action.tileCount == nil {
                HStack {
                    Text("Free keys:").font(.caption)
                    ForEach(controller.shortcuts.suggestions(system: system, limit: 4), id: \.self) { free in
                        Button(free.symbols) { commit(free, for: action) }.controlSize(.small)
                    }
                }
            }
            HStack {
                Button("Use Anyway") { commit(combo, for: action) }
                Button("Cancel", action: stopRecording)
            }
        }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        // Shortcuts must not fire while the user presses the keys they want.
        controller.hotKeys.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func handle(_ event: NSEvent, for action: ShortcutAction) {
        switch Int(event.keyCode) {
        case 53:
            stopRecording()
            return
        case 51, 117:
            controller.shortcuts.bindings[action.rawValue] = ShortcutMap.off
            stopRecording()
            return
        default:
            break
        }
        guard let key = ShortcutKey(keyCode: UInt32(event.keyCode)) else { return }
        var modifiers: KeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        // A shortcut needs a real modifier, and Tab View needs one to be held.
        guard !modifiers.subtracting(.shift).isEmpty else { return }
        let combo = KeyCombo(key: key, modifiers: modifiers)
        if controller.shortcuts.conflicts(for: combo, action: action, system: system).isEmpty {
            commit(combo, for: action)
        } else {
            candidate = combo
        }
    }

    private func commit(_ combo: KeyCombo, for action: ShortcutAction) {
        if action.tileCount != nil {
            controller.shortcuts.setTileModifiers(combo.modifiers)
        } else {
            controller.shortcuts.bindings[action.rawValue] = combo.string
        }
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        candidate = nil
        controller.registerHotKeys()
    }
}

private struct AppsSettings: View {
    @Bindable var controller: AppController

    private var addable: [NSRunningApplication] {
        AXWindowSystem.eligibleApps().filter {
            $0.bundleIdentifier.map { !controller.rules.excluded.contains($0) } ?? false
        }
    }

    var body: some View {
        Form {
            Section("Apps that are never tiled") {
                ForEach(controller.rules.excluded, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button {
                            controller.toggleTile(for: bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add App") {
                    ForEach(addable, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? "") {
                            if let bundleID = app.bundleIdentifier { controller.toggleTile(for: bundleID) }
                        }
                    }
                }
            }
            Section("Apps that can't shrink") {
                ForEach(controller.rules.learnedMinimums.keys.sorted(), id: \.self) { bundleID in
                    let size = controller.rules.learnedMinimums[bundleID] ?? .zero
                    LabeledContent(bundleID, value: "\(Int(size.width)) × \(Int(size.height))")
                }
                Button("Forget All") { controller.rules.learnedMinimums = [:] }
                    .disabled(controller.rules.learnedMinimums.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/juancasanueva/SWIFTUI_Terrazzo")!
    static let license = repository.appending(path: "blob/main/LICENSE")
}

private struct AboutSettings: View {
    @Bindable var controller: AppController

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim: version)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                        Text("Terrazzo")
                    }
                }
                LabeledContent("Config folder", value: ConfigDirectory.url().path)
                Button("Open Config Folder") { NSWorkspace.shared.open(ConfigDirectory.url()) }
                LabeledContent("License") {
                    Link("MIT License", destination: ProjectLinks.license)
                }
                LabeledContent("Source code") {
                    Link(destination: ProjectLinks.repository) { Text(verbatim: "GitHub") }
                }
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $controller.settings.automaticUpdateChecks)
                LabeledContent(UpdateCheckPresentation(lastCheck: controller.updater.lastUpdateCheckDate, now: .now).label) {
                    CheckForUpdatesButton(updater: controller.updater)
                }
            }
            Section {
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report(), forType: .string)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func report() -> String {
        let displays = Displays.current()
        return [
            "Terrazzo \(version)",
            ProcessInfo.processInfo.operatingSystemVersionString,
            "Displays: \(displays.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ", "))",
            "Status: \(controller.status)",
            "Stage Manager: \(controller.stageManagerOn)",
            "Learned apps: \(controller.rules.learnedMinimums.count)",
        ].joined(separator: "\n")
    }
}

/// Its own view so the panel and Settings re-render as the updater's state changes.
struct CheckForUpdatesButton: View {
    let updater: any AppUpdating

    var isDisabled: Bool { !updater.canCheckForUpdates }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(isDisabled)
    }
}
