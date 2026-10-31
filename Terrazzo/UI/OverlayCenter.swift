import AppKit
import SwiftUI

struct OverlayModel {
    var settings: AppSettings
    var state: TilingState
    var context: TilingContext
    var focused: WindowID?
    var noPeekOn: Bool
    var frontFrames: (WindowID) -> CGRect?
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#FF9500" }
        return String(
            format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255),
            Int(color.blueComponent * 255))
    }
}

extension AppSettings.StackBar {
    /// A color typed by hand into the config may not parse.
    var resolvedColor: NSColor {
        NSColor(hex: color) ?? NSColor(hex: Self().color) ?? .systemOrange
    }
}

extension CleanBackground {
    var color: NSColor {
        switch self {
        case .graphite: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1)
        case .mist: NSColor(srgbRed: 0.84, green: 0.87, blue: 0.89, alpha: 1)
        case .stone: NSColor(srgbRed: 0.62, green: 0.60, blue: 0.56, alpha: 1)
        }
    }
}

/// Every window the app draws over the desktop: borders, curtains, grips, highlights and notices.
final class OverlayCenter {
    private var borders: [WindowID: NSPanel] = [:]
    private var curtains: [String: CurtainPanel] = [:]
    private var grips: [WindowID: GripPanel] = [:]
    private var highlight: NSPanel?
    private var highlightLabel: NSTextField?
    private var noticePanel: NSPanel?
    private var noticeLabel: NSTextField?
    private var noticeTimer: Timer?

    static func makePanel(_ frame: CGRect, level: NSWindow.Level = .normal, clickThrough: Bool = true) -> NSPanel {
        let panel = NSPanel(
            contentRect: Displays.toAppKit(frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.ignoresMouseEvents = clickThrough
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }

    func hideAll() {
        borders.values.forEach { $0.orderOut(nil) }
        borders = [:]
        curtains.values.forEach { $0.orderOut(nil) }
        curtains = [:]
        grips.values.forEach { $0.orderOut(nil) }
        grips = [:]
        hideDropHighlight()
    }

    func update(_ model: OverlayModel, controller: AppController) {
        updateCurtains(model)
        updateBorders(model)
        updateGrips(model, controller: controller)
    }

    // MARK: Borders

    private func updateBorders(_ model: OverlayModel) {
        let style = model.settings.highlight.style
        var wanted: [WindowID: CGRect] = [:]
        if style != .none {
            for screen in model.context.screens {
                guard let workspace = model.state.workspaces[screen.key] else { continue }
                let showing = workspace.cleanSet ?? workspace.tiles.compactMap(\.windows.first)
                for id in showing where style != .activeBorder && style != .glow || id == model.focused {
                    if let frame = model.frontFrames(id) { wanted[id] = frame }
                }
            }
        }
        for (id, panel) in borders where wanted[id] == nil {
            panel.orderOut(nil)
            borders[id] = nil
        }
        let color = NSColor(hex: model.settings.highlight.color) ?? .systemOrange
        let width = CGFloat(model.settings.highlight.width)
        for (id, frame) in wanted {
            let outset = style == .glow ? 16 : width
            let rect = frame.insetBy(dx: -outset, dy: -outset)
            let panel = borders[id] ?? Self.makePanel(rect)
            borders[id] = panel
            panel.setFrame(Displays.toAppKit(rect), display: false)
            let view = panel.contentView ?? NSView()
            view.wantsLayer = true
            view.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            let ring = CALayer()
            ring.frame = view.bounds.insetBy(dx: outset - width, dy: outset - width)
            ring.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            ring.cornerRadius = CGFloat(model.settings.highlight.outerRadius)
            ring.cornerCurve = .continuous
            ring.borderWidth = width
            ring.borderColor = color.cgColor
            if style == .glow {
                ring.shadowColor = color.cgColor
                ring.shadowOpacity = 0.9
                ring.shadowRadius = 10
                ring.shadowOffset = .zero
            }
            view.layer?.addSublayer(ring)
            panel.order(.above, relativeTo: Int(id))
        }
    }

    // MARK: Curtains

    private func updateCurtains(_ model: OverlayModel) {
        var wanted: Set<String> = []
        for screen in model.context.screens {
            guard let display = Displays.current().first(where: { $0.uuid == screen.key.display }) else { continue }
            let clean = model.state.workspaces[screen.key]?.cleanSet
            let mode: CurtainPanel.Mode?
            if clean != nil {
                mode = .clean(model.settings.cleanBackground.color)
            } else if model.noPeekOn {
                mode = .dim(amount: model.settings.noPeek.dim / 100, blur: model.settings.noPeek.blur)
            } else {
                mode = nil
            }
            guard let mode else { continue }
            wanted.insert(display.uuid)
            let curtain = curtains[display.uuid] ?? CurtainPanel()
            curtains[display.uuid] = curtain
            curtain.configure(mode: mode, frame: display.frame)
            if let clean, let lowest = clean.first {
                for id in clean { model.state.apps[id].map { _ in AppController.shared.ax.raise(id) } }
                curtain.order(.below, relativeTo: Int(lowest))
            } else if clean != nil {
                curtain.orderFrontRegardless()
            } else if let focused = model.focused {
                curtain.order(.below, relativeTo: Int(focused))
            } else {
                curtain.orderFrontRegardless()
            }
        }
        for (uuid, curtain) in curtains where !wanted.contains(uuid) {
            curtain.orderOut(nil)
            curtains[uuid] = nil
        }
    }

    // MARK: Grips

    private func updateGrips(_ model: OverlayModel, controller: AppController) {
        var seen: Set<WindowID> = []
        for screen in model.context.screens {
            guard let workspace = model.state.workspaces[screen.key], workspace.cleanSet == nil,
                workspace.zoomed == nil
            else { continue }
            let frames = model.state.slotFrames(on: screen.key, context: model.context)
            for (index, tile) in workspace.tiles.enumerated() {
                guard let shown = tile.windows.first, let frame = frames[safe: index] else { continue }
                let isActive = tile.windows.contains { $0 == model.focused }
                // A plain inactive tile has nothing to show.
                guard isActive || tile.windows.count > 1 else { continue }
                seen.insert(shown)
                let panel = grips[shown] ?? GripPanel(controller: controller)
                grips[shown] = panel
                panel.show(
                    windows: tile.windows, isActive: isActive, above: frame, gap: model.context.policy.gap,
                    style: model.settings.stackBar)
            }
        }
        for (id, panel) in grips where !seen.contains(id) {
            panel.orderOut(nil)
            grips[id] = nil
        }
    }

    // MARK: Drop highlight

    func showDropHighlight(_ frame: CGRect, text: String) {
        let panel = highlight ?? Self.makePanel(frame, level: .floating)
        if highlight == nil {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
            view.layer?.borderColor = NSColor.systemOrange.cgColor
            view.layer?.borderWidth = 2
            view.layer?.cornerRadius = 12
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 22, weight: .semibold)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            panel.contentView = view
            highlight = panel
            highlightLabel = label
        }
        highlightLabel?.stringValue = text
        panel.setFrame(Displays.toAppKit(frame), display: true)
        panel.orderFrontRegardless()
    }

    func hideDropHighlight() {
        highlight?.orderOut(nil)
    }

    // MARK: Notices

    func showNotice(_ text: String) {
        guard let display = Displays.display(containing: Displays.pointerLocation(), in: Displays.current()) else {
            return
        }
        let size = CGSize(width: min(640, CGFloat(text.count) * 9 + 48), height: 40)
        let frame = CGRect(
            x: display.visibleFrame.midX - size.width / 2, y: display.visibleFrame.maxY - size.height - 32,
            width: size.width, height: size.height)
        let panel = noticePanel ?? Self.makePanel(frame, level: .statusBar)
        if noticePanel == nil {
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 10
            background.layer?.masksToBounds = true
            let label = NSTextField(labelWithString: text)
            label.alignment = .center
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            ])
            panel.contentView = background
            noticePanel = panel
            noticeLabel = label
        }
        noticeLabel?.stringValue = text
        panel.setFrame(Displays.toAppKit(frame), display: true)
        panel.orderFrontRegardless()
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
    }
}

/// Covers one screen just below the active window, for No peek and Clean Space.
final class CurtainPanel: NSPanel {
    enum Mode: Equatable {
        case dim(amount: Double, blur: Bool)
        case clean(NSColor)
    }

    private var mode: Mode?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .normal
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    func configure(mode: Mode, frame: CGRect) {
        setFrame(Displays.toAppKit(frame), display: false)
        guard mode != self.mode else { return }
        self.mode = mode
        let container = NSView()
        container.wantsLayer = true
        switch mode {
        case .clean(let color):
            container.layer?.backgroundColor = color.cgColor
        case .dim(let amount, let blur):
            if blur {
                let effect = NSVisualEffectView(frame: container.bounds)
                effect.autoresizingMask = [.width, .height]
                effect.blendingMode = .behindWindow
                effect.material = .fullScreenUI
                effect.state = .active
                container.addSubview(effect)
            }
            let dim = NSView(frame: container.bounds)
            dim.autoresizingMask = [.width, .height]
            dim.wantsLayer = true
            dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(amount).cgColor
            container.addSubview(dim)
        }
        contentView = container
    }
}
