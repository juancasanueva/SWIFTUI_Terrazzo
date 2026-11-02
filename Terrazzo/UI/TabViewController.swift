import AppKit
import SwiftUI

struct TabEntry: Identifiable, Equatable {
    var id: WindowID
    /// Position on the desktop, in window-system coordinates. Empty for minimized windows.
    var frame: CGRect
    var appName: String
    var title: String
    var pid: pid_t
    var isMinimized: Bool
    /// Sits over the tiles, so its card needs an outline to stand out from the cards beneath it.
    var isFloating = false
}

struct TabScreen: Identifiable, Equatable {
    var id: String
    var name: String
    var frame: CGRect
    var entries: [TabEntry]
    var minimized: [TabEntry]
}

@Observable
final class TabViewModel {
    var screens: [TabScreen] = []
    var selection: WindowID?
    var onChoose: ((WindowID) -> Void)?

    var ordered: [TabEntry] { screens.flatMap { $0.entries + $0.minimized } }
}

/// Every window, screen by screen, while a modifier is held. Titles are read when it opens and
/// dropped when it closes.
final class TabViewController {
    private unowned let controller: AppController
    private let model = TabViewModel()
    private var panel: NSPanel?
    private var releaseTimer: Timer?
    private var heldModifiers: NSEvent.ModifierFlags = []

    init(controller: AppController) {
        self.controller = controller
    }

    var isOpen: Bool { panel?.isVisible == true }

    func pressed(backward: Bool) {
        if isOpen {
            advance(backward: backward)
        } else {
            open(backward: backward)
        }
    }

    private func open(backward: Bool) {
        model.screens = buildScreens()
        let ordered = model.ordered
        guard !ordered.isEmpty else { return }
        let ids = Set(ordered.map(\.id))
        let recent = controller.recentWindows.filter { ids.contains($0) }
        model.selection = (recent.count > 1 ? recent[1] : recent.first) ?? ordered[0].id
        model.onChoose = { [weak self] id in self?.commit(id) }

        heldModifiers = Self.flags(controller.shortcuts.combo(for: .tabView)?.modifiers ?? .control)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let display =
            Displays.display(containing: Displays.pointerLocation(), in: Displays.current())?.visibleFrame ?? .zero
        let size = TabViewContent.preferredSize(for: model.screens)
        let frame = CGRect(
            x: display.midX - size.width / 2, y: display.midY - size.height / 2, width: size.width,
            height: size.height)
        panel.setFrame(Displays.toAppKit(frame), display: true)
        panel.orderFrontRegardless()

        // The panel never takes keyboard focus, so the active app keeps it until the user switches.
        controller.hotKeys.registerTemporary(
            [.left, .right, .up, .down, .return, .escape],
            modifiers: controller.shortcuts.combo(for: .tabView)?.modifiers ?? .control
        ) { [weak self] key in self?.handle(key) }
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRelease() }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TabViewContent(model: model))
        return panel
    }

    private func buildScreens() -> [TabScreen] {
        let context = controller.context()
        let excludedRecords = controller.ax.scan(pid: nil)
        return orderedDisplays().map { display in
            let onScreen = excludedRecords.filter {
                Displays.display(for: $0.frame, in: [display]) != nil
                    && Displays.display(for: $0.frame, in: Displays.current())?.uuid == display.uuid
            }
            var entries: [TabEntry] = []
            var minimized: [TabEntry] = []
            var placed: Set<WindowID> = []

            let key = context.screens.first { $0.key.display == display.uuid }?.key
            if let key, let workspace = controller.state.workspaces[key] {
                let frames = controller.state.slotFrames(on: key, context: context)
                for (slot, tile) in workspace.tiles.enumerated() {
                    guard let frame = frames[safe: slot] else { continue }
                    // Stacked windows share their tile side by side, so each can be picked.
                    let width = frame.width / CGFloat(tile.windows.count)
                    for (index, id) in tile.windows.enumerated() {
                        guard let record = controller.ax.record(id) else { continue }
                        placed.insert(id)
                        let part = CGRect(
                            x: frame.minX + CGFloat(index) * width, y: frame.minY, width: width,
                            height: frame.height)
                        entries.append(entry(record, frame: part))
                    }
                }
            }
            for record in onScreen where !placed.contains(record.id) {
                // Parked windows of other workspaces go in the row under the desktop, ready to pick.
                if record.isMinimized || controller.isParked(record.id) {
                    minimized.append(entry(record, frame: .zero))
                } else if record.isTileable {
                    entries.append(entry(record, frame: record.frame, isFloating: true))
                }
            }
            return TabScreen(
                id: display.uuid, name: display.name, frame: display.frame, entries: entries, minimized: minimized)
        }
        .filter { !$0.entries.isEmpty || !$0.minimized.isEmpty }
    }

    /// Left to right as arranged in System Settings, not primary display first.
    private func orderedDisplays() -> [DisplayInfo] {
        Displays.current().sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    private func entry(_ record: WindowRecord, frame: CGRect, isFloating: Bool = false) -> TabEntry {
        TabEntry(
            id: record.id, frame: frame, appName: record.appName, title: controller.ax.title(of: record.id),
            pid: record.pid, isMinimized: record.isMinimized, isFloating: isFloating)
    }

    private func advance(backward: Bool) {
        let ordered = model.ordered
        guard let current = ordered.firstIndex(where: { $0.id == model.selection }) else { return }
        let next = (current + (backward ? -1 : 1) + ordered.count) % ordered.count
        model.selection = ordered[next].id
    }

    func moveSelection(_ direction: Direction) {
        let entries = model.screens.flatMap(\.entries)
        guard let current = entries.first(where: { $0.id == model.selection }) else { return }
        let frames = entries.map(\.frame)
        if let index = TilingState.neighbor(of: current.frame, in: frames, direction: direction) {
            model.selection = entries[index].id
        }
    }

    private func handle(_ key: ShortcutKey) {
        switch key {
        case .escape:
            close()
        case .return:
            if let selection = model.selection { commit(selection) }
        case .left:
            moveSelection(.left)
        case .right:
            moveSelection(.right)
        case .down:
            moveSelection(.down)
        case .up:
            moveSelection(.up)
        default:
            break
        }
    }

    private func checkRelease() {
        let current = NSEvent.modifierFlags.intersection([.control, .option, .command])
        let needed = heldModifiers.intersection([.control, .option, .command])
        guard current.intersection(needed).isEmpty, !needed.isEmpty else { return }
        if let selection = model.selection {
            commit(selection)
        } else {
            close()
        }
    }

    private func commit(_ id: WindowID) {
        close()
        controller.showWindow(id)
    }

    private func close() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        controller.hotKeys.unregisterTemporary()
        panel?.orderOut(nil)
        model.screens = []
        model.selection = nil
    }

    private static func flags(_ modifiers: KeyModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }
}

private struct TabViewContent: View {
    @Bindable var model: TabViewModel

    private static let screenWidth: CGFloat = 460
    private static let iconSize: CGFloat = 48
    private static let smallestIconSize: CGFloat = 24
    /// Tall enough for a full-size icon above the two lines of text.
    private static let minimizedCardHeight: CGFloat = 88

    static func preferredSize(for screens: [TabScreen]) -> CGSize {
        let width = CGFloat(screens.count) * (screenWidth + 16) + 32
        let tallest = screens.map { screenHeight($0) }.max() ?? 280
        let hasMinimized = screens.contains { !$0.minimized.isEmpty }
        return CGSize(width: width, height: tallest + (hasMinimized ? 60 + minimizedCardHeight : 100))
    }

    private static func screenHeight(_ screen: TabScreen) -> CGFloat {
        screenWidth * screen.frame.height / max(screen.frame.width, 1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(model.screens) { screen in
                VStack(alignment: .leading, spacing: 8) {
                    Text(screen.name).font(.caption).foregroundStyle(.secondary)
                    desktop(screen)
                    if !screen.minimized.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(screen.minimized) { entry in
                                card(entry).frame(width: 120, height: Self.minimizedCardHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func desktop(_ screen: TabScreen) -> some View {
        let scale = Self.screenWidth / max(screen.frame.width, 1)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
            ForEach(screen.entries) { entry in
                card(entry)
                    .frame(width: max(entry.frame.width * scale - 4, 40), height: max(entry.frame.height * scale - 4, 30))
                    .offset(
                        x: (entry.frame.minX - screen.frame.minX) * scale + 2,
                        y: (entry.frame.minY - screen.frame.minY) * scale + 2)
            }
        }
        .frame(width: Self.screenWidth, height: Self.screenHeight(screen))
        .clipped()
    }

    private func card(_ entry: TabEntry) -> some View {
        VStack(spacing: 2) {
            if let icon = NSRunningApplication(processIdentifier: entry.pid)?.icon {
                // Shrinks on a tile too short for it, so the text stays inside the card.
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    .frame(
                        minWidth: Self.smallestIconSize, maxWidth: Self.iconSize,
                        minHeight: Self.smallestIconSize, maxHeight: Self.iconSize)
            }
            Text(entry.appName).font(.caption.weight(.semibold)).lineLimit(1)
            Text(entry.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if model.selection == entry.id {
                RoundedRectangle(cornerRadius: 6).stroke(Color.orange, lineWidth: 2)
            } else if entry.isFloating {
                RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.onChoose?(entry.id) }
    }
}
