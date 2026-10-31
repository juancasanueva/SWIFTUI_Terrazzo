import AppKit
import Carbon.HIToolbox
import Observation
import ServiceManagement

enum TilingStatus: Equatable {
    case tiling(count: Int, focus: Bool)
    case stageManager, waitingForSetup, off, needsAccess

    var isTiling: Bool {
        if case .tiling = self { return true }
        return false
    }
}

/// Connects the pure tiling state to the window system, the config files and the interface.
@Observable
final class AppController {
    static let shared = AppController()

    // MARK: Config files

    @ObservationIgnored private let directory = ConfigDirectory.url()
    @ObservationIgnored private lazy var settingsFile = ConfigFile(
        url: directory.appendingPathComponent("settings.json"), defaults: AppSettings())
    @ObservationIgnored private lazy var shortcutsFile = ConfigFile(
        url: directory.appendingPathComponent("shortcuts.json"), defaults: ShortcutMap())
    @ObservationIgnored private lazy var rulesFile = ConfigFile(
        url: directory.appendingPathComponent("apps.json"), defaults: AppRules())
    @ObservationIgnored private lazy var screensFile = ConfigFile(
        url: directory.appendingPathComponent("screens.json"), defaults: ScreensFile())
    @ObservationIgnored private let watcher = ConfigWatcher()
    @ObservationIgnored private var isLoadingConfig = false

    var settings = AppSettings() {
        didSet {
            guard settings != oldValue else { return }
            if !isLoadingConfig { save(settings, to: settingsFile) }
            settingsChanged(from: oldValue)
        }
    }

    var shortcuts = ShortcutMap() {
        didSet {
            guard shortcuts != oldValue else { return }
            if !isLoadingConfig { save(shortcuts, to: shortcutsFile) }
            registerHotKeys()
        }
    }

    var rules = AppRules() {
        didSet {
            guard rules != oldValue else { return }
            if !isLoadingConfig { save(rules, to: rulesFile) }
            state.refreshLimits(context: context())
            scheduleRefresh(pid: nil)
        }
    }

    @ObservationIgnored private var screens = ScreensFile()
    /// Names the file whose contents could not be used, while the last good values stay in force.
    var configError: String?

    // MARK: System state

    @ObservationIgnored let ax = AXWindowSystem()
    @ObservationIgnored let hotKeys = HotKeyCenter()
    @ObservationIgnored let overlays = OverlayCenter()
    @ObservationIgnored private let spaces = SpaceReader()
    @ObservationIgnored private lazy var dragTracker = DragTracker(controller: self)
    @ObservationIgnored private lazy var hoverFocus = HoverFocus(controller: self)
    @ObservationIgnored lazy var tabView = TabViewController(controller: self)

    var isTrusted = AXWindowSystem.isTrusted
    var stageManagerOn = false
    var secureInputOn = false
    var hotKeysFailed = false
    var state = TilingState()
    var noPeekOn = false
    var workspaceMap = VirtualWorkspaces()
    var settingsTab = SettingsTab.general
    var isSetupWindowOpen = false
    /// The app in front, for the panel's per-app switch.
    var frontApp: NSRunningApplication?
    /// Bumped after each refresh so the panel preview follows the windows.
    var revision = 0

    /// Windows parked in a corner because their workspace isn't showing.
    @ObservationIgnored private var hiddenWindows: Set<WindowID> = []
    @ObservationIgnored private var lastWorkspaceSwitch = Date.distantPast
    @ObservationIgnored private var terminationSource: DispatchSourceSignal?
    @ObservationIgnored private var pendingPids: Set<pid_t> = []
    @ObservationIgnored private var followUps: Set<pid_t> = []
    @ObservationIgnored private var suspectedMinimums: [WindowID: CGSize] = [:]
    @ObservationIgnored private var pendingAll = false
    @ObservationIgnored private var refreshScheduled = false
    @ObservationIgnored private var lastShowing: Set<WindowID> = []
    @ObservationIgnored private var lastApplied: [WindowID: (requested: CGRect, accepted: CGRect)] = [:]
    @ObservationIgnored private(set) var recentWindows: [WindowID] = []
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var started = false

    var isOperating: Bool {
        isTrusted && settings.setupFinished && settings.tilingEnabled && !stageManagerOn
    }

    var status: TilingStatus {
        if !isTrusted { return .needsAccess }
        if !settings.setupFinished { return .waitingForSetup }
        if !settings.tilingEnabled { return .off }
        if stageManagerOn { return .stageManager }
        let key = pointerKey()
        let workspace = key.flatMap { state.workspaces[$0] }
        return .tiling(count: workspace?.tiles.reduce(0) { $0 + $1.windows.count } ?? 0, focus: workspace?.zoomed != nil)
    }

    var hasCleanSpace: Bool { state.workspaces.values.contains { $0.cleanSet != nil } }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        reloadConfig()
        watcher.onChange = { [weak self] in self?.reloadConfig() }
        watcher.start(directory: directory)
        ax.onChange = { [weak self] pid in self?.windowsChanged(pid: pid) }
        hotKeys.onPress = { [weak self] action in self?.perform(action) }

        let workspace = NSWorkspace.shared.notificationCenter
        let refreshAll: (Notification) -> Void = { [weak self] _ in self?.scheduleRefresh(pid: nil) }
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didActivateApplicationNotification,
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main, using: refreshAll)
        }
        // A launching app has no windows yet, and may not answer until it finishes starting.
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {
            [weak self] _ in
            for delay in [1.0, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.scheduleRefresh(pid: nil) }
            }
        }
        let endClean: (Notification) -> Void = { [weak self] _ in self?.endCleanSpaces() }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: endClean)
        workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: endClean)
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: endClean)
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: refreshAll)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refreshAll)

        // A plain `kill` must also bring parked windows back.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source

        syncWorkspaces()
        applyAppearance()
        pollSystemState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSystemState() }
        }
        operatingChanged()
    }

    /// Accessibility access, Stage Manager and Secure Input have no change notification to rely on.
    private func pollSystemState() {
        let wasOperating = isOperating
        let trusted = AXWindowSystem.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
            if trusted { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default) }
        }
        let stage = SystemState.stageManagerEnabled
        if stage != stageManagerOn { stageManagerOn = stage }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInputOn { secureInputOn = secure }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != frontApp?.processIdentifier { frontApp = front }
        if wasOperating != isOperating { operatingChanged() }
    }

    private func operatingChanged() {
        if isOperating {
            registerHotKeys()
            dragTracker.start()
            hoverFocus.update(enabled: settings.hoverFocus)
            scheduleRefresh(pid: nil)
        } else {
            // Windows stay where they are, except parked ones, which would be out of reach.
            revealHiddenWindows()
            hotKeys.unregisterAll()
            dragTracker.stop()
            hoverFocus.update(enabled: false)
            overlays.hideAll()
            ax.forgetAll()
            noPeekOn = false
            lastApplied = [:]
        }
    }

    func registerHotKeys() {
        guard isOperating else { return }
        hotKeysFailed = !hotKeys.register(shortcuts.active).isEmpty
    }

    func finishSetup() {
        var updated = settings
        updated.setupFinished = true
        settings = updated
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        applyLoginItem()
        operatingChanged()
    }

    // MARK: Config

    private func reloadConfig() {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        var problems: [String] = []
        func load<Value>(_ file: ConfigFile<Value>, into apply: (Value) -> Void) {
            do {
                apply(try file.load())
            } catch {
                problems.append(file.url.lastPathComponent)
            }
        }
        load(settingsFile) { settings = $0 }
        load(shortcutsFile) { shortcuts = $0 }
        load(rulesFile) { rules = $0 }
        load(screensFile) { screens = $0 }
        applyScreenPreferencesToWorkspaces()
        let message = problems.isEmpty ? nil : problems.joined(separator: ", ")
        if message != configError {
            configError = message
            if let message {
                overlays.showNotice(String(localized: "\(message) has an error. Keeping the last good values."))
            }
        }
    }

    private func save<Value>(_ value: Value, to file: ConfigFile<Value>) {
        do {
            try file.save(value)
        } catch {
            configError = file.url.lastPathComponent
            overlays.showNotice(
                String(localized: "\(file.url.lastPathComponent) has an error. Fix it to save this change."))
        }
    }

    private func saveScreenPreferences(_ key: WorkspaceKey) {
        guard let workspace = state.workspaces[key] else { return }
        screens.screens[ScreensFile.id(key)] = ScreenPreferences(
            kind: workspace.kind, count: workspace.count, overrides: workspace.overrides)
        save(screens, to: screensFile)
    }

    private func hydrate(_ key: WorkspaceKey) {
        guard state.workspaces[key] == nil else { return }
        var workspace = Workspace()
        if let stored = screens.screens[ScreensFile.id(key)] {
            workspace.kind = stored.kind
            workspace.count = stored.count
            workspace.overrides = stored.overrides
        }
        state.workspaces[key] = workspace
    }

    private func applyScreenPreferencesToWorkspaces() {
        var changed = false
        for key in state.workspaces.keys {
            guard let stored = screens.screens[ScreensFile.id(key)], var workspace = state.workspaces[key] else {
                continue
            }
            if workspace.kind != stored.kind || workspace.count != stored.count
                || workspace.overrides != stored.overrides {
                workspace.kind = stored.kind
                workspace.count = stored.count
                workspace.overrides = stored.overrides
                state.workspaces[key] = workspace
                changed = true
            }
        }
        if changed {
            state.refreshLimits(context: context())
            scheduleRefresh(pid: nil)
        }
    }

    private func settingsChanged(from old: AppSettings) {
        if old.appearance != settings.appearance || old.iconStyle != settings.iconStyle { applyAppearance() }
        if old.openAtLogin != settings.openAtLogin { applyLoginItem() }
        if old.hoverFocus != settings.hoverFocus { hoverFocus.update(enabled: settings.hoverFocus && isOperating) }
        if let language = settings.language, language != old.language {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        } else if settings.language == nil, old.language != nil {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        if old.tilingEnabled != settings.tilingEnabled || old.setupFinished != settings.setupFinished {
            operatingChanged()
            return
        }
        state.refreshLimits(context: context())
        if isOperating { scheduleRefresh(pid: nil) }
    }

    private func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.applicationIconImage = AppIconRenderer.image(for: settings.iconStyle)
    }

    private func applyLoginItem() {
        guard settings.setupFinished else { return }
        do {
            if settings.openAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            overlays.showNotice(String(localized: "Could not change the Open at login setting."))
        }
    }

    // MARK: Refresh

    func scheduleRefresh(pid: pid_t?) {
        if let pid { pendingPids.insert(pid) } else { pendingAll = true }
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshNow()
        }
    }

    /// A closing window can still be listed when its notification arrives, so look again shortly after.
    private func windowsChanged(pid: pid_t) {
        scheduleRefresh(pid: pid)
        guard followUps.insert(pid).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.followUps.remove(pid)
            self?.scheduleRefresh(pid: pid)
        }
    }

    private func refreshNow() {
        // A locked session reports no windows at all; believing it would forget the whole layout.
        guard isOperating, !dragTracker.isActive, !SystemState.isSessionLocked else { return }
        let all = pendingAll
        let pids = pendingPids
        pendingAll = false
        pendingPids = []

        var records: [WindowRecord] = []
        if all {
            records = ax.scan(pid: nil)
        } else {
            for pid in pids { records = ax.scan(pid: pid) }
        }

        let displays = Displays.current()
        syncWorkspaces()
        let focused = ax.focusedWindow()
        followFocusToWorkspace(focused)
        let context = context(displays: displays)
        context.screens.forEach { hydrate($0.key) }
        for key in state.workspaces.keys where state.workspaces[key]?.cleanSet != nil {
            if !displays.contains(where: { $0.uuid == key.display }) { state.workspaces[key]?.cleanSet = nil }
        }

        let excluded = Set(rules.excluded)
        var windows: [ObservedWindow] = []
        for record in records where record.isTileable && !record.isMinimized && !excluded.contains(record.bundleID) {
            if isParked(record.id, displays: displays) { continue }
            guard let key = key(for: record, displays: displays) else { continue }
            windows.append(ObservedWindow(id: record.id, app: record.bundleID, key: key, frame: record.frame))
        }
        // Order is opening order: window numbers grow as windows are created.
        windows.sort { $0.id < $1.id }

        if let focused {
            recentWindows.removeAll { $0 == focused }
            recentWindows.insert(focused, at: 0)
        }
        let snapshot = Snapshot(
            windows: windows, minimized: records.filter(\.isMinimized).map(\.id), focused: focused,
            focusedApp: focusedOtherApp(), existing: Self.existingWindows())
        show(state.reconcile(snapshot, context: context))
        apply(context: context)
    }

    private func focusedOtherApp() -> String? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == getpid() ? nil : app?.bundleIdentifier
    }

    /// Window numbers on every Space, hidden or not. Uses numbers only.
    private static func existingWindows() -> Set<WindowID>? {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    private func key(for record: WindowRecord, displays: [DisplayInfo]) -> WorkspaceKey? {
        guard let display = Displays.display(for: record.frame, in: displays) else { return nil }
        let active = spaces.activeSpace(ofDisplay: display.uuid)
        let windowSpaces = spaces.spaces(ofWindow: record.id)
        if !windowSpaces.isEmpty, active != 0, !windowSpaces.contains(active) { return nil }
        return WorkspaceKey(display: display.uuid, space: active, virtual: workspaceMap.number(on: display.uuid))
    }

    private func visibleKey(_ display: String) -> WorkspaceKey {
        WorkspaceKey(
            display: display, space: spaces.activeSpace(ofDisplay: display),
            virtual: workspaceMap.number(on: display))
    }

    /// True for windows of a workspace that isn't showing on their current Space and connected display.
    private func isParked(_ id: WindowID, displays: [DisplayInfo]) -> Bool {
        guard let stored = state.key(of: id), displays.contains(where: { $0.uuid == stored.display }) else {
            return false
        }
        return stored.space == spaces.activeSpace(ofDisplay: stored.display) && !isShown(stored)
    }

    func isShown(_ key: WorkspaceKey) -> Bool {
        key.virtual == workspaceMap.number(on: key.display)
    }

    func isParked(_ id: WindowID) -> Bool { hiddenWindows.contains(id) }

    private func syncWorkspaces() {
        var updated = workspaceMap
        updated.sync(displays: Displays.current().map(\.uuid))
        if updated != workspaceMap { workspaceMap = updated }
    }

    /// Cmd-Tab, the Dock or a notification can pick a parked window: go to its workspace. Only a change
    /// of focus counts, and not right after a switch, when the old window may still report focus.
    private func followFocusToWorkspace(_ focused: WindowID?) {
        guard let focused, focused != state.focused, Date().timeIntervalSince(lastWorkspaceSwitch) > 0.7,
            let key = state.key(of: focused), isParked(focused, displays: Displays.current())
        else { return }
        _ = workspaceMap.show(key.virtual, focusedDisplay: key.display, isEmpty: false)
    }

    // MARK: Workspaces

    func isWorkspaceEmpty(_ number: Int) -> Bool {
        !state.workspaces.contains { key, workspace in
            key.virtual == number && (!workspace.tiles.isEmpty || !workspace.overflow.isEmpty)
        }
    }

    func switchToWorkspace(_ number: Int) {
        guard isOperating else { return }
        syncWorkspaces()
        guard let focusedDisplay = activeKey()?.display else { return }
        let display = workspaceMap.show(number, focusedDisplay: focusedDisplay, isEmpty: isWorkspaceEmpty(number))
        lastWorkspaceSwitch = Date()
        let key = visibleKey(display)
        hydrate(key)
        apply()
        focusShowingWindow(on: key)
    }

    func moveFocusedWindow(toWorkspace number: Int) {
        guard isOperating, let id = shownFocusedWindow(), let source = state.key(of: id) else { return }
        syncWorkspaces()
        let display =
            workspaceMap.display(showing: number)
            ?? (isWorkspaceEmpty(number) ? nil : workspaceMap.home(of: number))
            ?? source.display
        let target = WorkspaceKey(
            display: display, space: spaces.activeSpace(ofDisplay: display), virtual: number)
        guard target != source else { return }
        hydrate(target)
        workspaceMap.adopt(number, on: display)
        lastWorkspaceSwitch = Date()
        _ = state.send(id, to: target, context: context())
        apply()
        focusShowingWindow(on: source)
    }

    /// With nothing to focus, keyboard input must not keep going to a parked window.
    private func focusShowingWindow(on key: WorkspaceKey) {
        let workspace = state.workspaces[key]
        if let id = workspace.flatMap({ $0.tiles[safe: $0.activeTile]?.windows.first ?? $0.tiles.first?.windows.first }) {
            ax.focus(id)
            state.focused = id
            apply()
        } else {
            state.focused = nil
            NSApp.activate()
        }
    }

    private func hideWindowsOfOtherWorkspaces(context: TilingContext) {
        let displays = Displays.current()
        for (key, workspace) in state.workspaces where !isShown(key) {
            guard let display = displays.first(where: { $0.uuid == key.display }),
                key.space == spaces.activeSpace(ofDisplay: key.display)
            else { continue }
            let others = displays.filter { $0.uuid != display.uuid }.map(\.frame)
            for id in state.allWindows(on: key) where !hiddenWindows.contains(id) && !workspace.tiles.isEmpty {
                guard let frame = ax.currentFrame(of: id) else { continue }
                ax.move(
                    id,
                    to: VirtualWorkspaces.hiddenOrigin(display: display.frame, others: others, windowSize: frame.size))
                hiddenWindows.insert(id)
                lastApplied[id] = nil
            }
        }
    }

    /// Puts parked windows back on screen, for when this app stops managing them.
    func revealHiddenWindows() {
        let displays = Displays.current()
        for (index, id) in hiddenWindows.sorted().enumerated() {
            let home = state.key(of: id).flatMap { key in displays.first { $0.uuid == key.display } } ?? displays.first
            guard let home else { continue }
            let offset = CGFloat(index % 8) * 32
            ax.move(id, to: CGPoint(x: home.visibleFrame.minX + 40 + offset, y: home.visibleFrame.minY + 40 + offset))
        }
        hiddenWindows = []
    }

    func context(displays: [DisplayInfo] = Displays.current()) -> TilingContext {
        var policy = TilingPolicy(
            gap: CGFloat(settings.gap), whenFull: settings.whenFull, movingIntoFull: settings.movingIntoFull)
        policy.kind = settings.layout ?? .grid
        policy.kindIsChosen = settings.layout != nil
        policy.count = settings.windowsPerScreen
        policy.main = settings.mainSize
        let learned = rules.learnedMinimums
        let screens = displays.map { display -> ScreenGeometry in
            let edges = settings.screenEdgesByDisplay[display.uuid] ?? settings.screenEdges
            let area = CGRect(
                x: display.visibleFrame.minX + edges.left, y: display.visibleFrame.minY + edges.top,
                width: display.visibleFrame.width - edges.left - edges.right,
                height: display.visibleFrame.height - edges.top - edges.bottom)
            return ScreenGeometry(
                key: visibleKey(display.uuid),
                area: area)
        }
        return TilingContext(screens: screens, policy: policy, minimumSize: { learned[$0] ?? .zero })
    }

    /// Puts every window where the plan says. Returns how many actually had to move.
    @discardableResult
    func apply(context: TilingContext? = nil, depth: Int = 0) -> Int {
        guard isOperating else { return 0 }
        let context = context ?? self.context()
        let plan = state.plan(context: context)
        var moved = 0
        var learnedNewMinimum = false

        for placement in plan.placements {
            guard let live = ax.currentFrame(of: placement.id) else { continue }
            if Self.close(live, placement.frame) { continue }
            if let last = lastApplied[placement.id], last.requested == placement.frame,
                Self.close(live, last.accepted) {
                continue  // The app already refused this exact frame.
            }
            guard let accepted = ax.setFrame(placement.id, to: placement.frame) else { continue }
            lastApplied[placement.id] = (placement.frame, accepted)
            moved += 1
            if learnMinimum(id: placement.id, requested: placement.frame, accepted: accepted) {
                learnedNewMinimum = true
            }
        }

        for id in plan.centered { center(id, context: context) }
        for placement in plan.placements { hiddenWindows.remove(placement.id) }
        hideWindowsOfOtherWorkspaces(context: context)

        let showing = Set(plan.showing)
        for id in plan.showing where !lastShowing.contains(id) { ax.raise(id) }
        lastShowing = showing
        for screen in context.screens {
            if let zoomed = state.workspaces[screen.key]?.zoomed { ax.raise(zoomed) }
        }
        if let focused = state.focused, showing.contains(focused) { ax.raise(focused) }

        if learnedNewMinimum, depth < 2 {
            state.refreshLimits(context: context)
            return moved + apply(context: context, depth: depth + 1)
        }
        updateOverlays(context: context)
        revision &+= 1
        return moved
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1.5 && abs(a.minY - b.minY) < 1.5 && abs(a.width - b.width) < 1.5
            && abs(a.height - b.height) < 1.5
    }

    /// Records a size the app refused to go below. Small differences are grid rounding, as in terminals.
    /// A single refusal proves nothing: the app may be animating or mid-drag. It must refuse the same
    /// way again shortly after before the size is remembered.
    private func learnMinimum(id: WindowID, requested: CGRect, accepted: CGRect) -> Bool {
        guard let app = state.apps[id] else { return false }
        let tolerance: CGFloat = 24
        let refusedWidth = accepted.width > requested.width + tolerance
        let refusedHeight = accepted.height > requested.height + tolerance
        guard refusedWidth || refusedHeight else {
            suspectedMinimums[id] = nil
            return false
        }
        guard NSEvent.pressedMouseButtons == 0 else { return false }
        if let suspected = suspectedMinimums[id], abs(suspected.width - accepted.width) < 2,
            abs(suspected.height - accepted.height) < 2 {
            suspectedMinimums[id] = nil
        } else {
            suspectedMinimums[id] = accepted.size
            lastApplied[id] = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.scheduleRefresh(pid: nil)
            }
            return false
        }
        let current = rules.learnedMinimums[app] ?? .zero
        var updated = current
        if refusedWidth { updated.width = max(current.width, accepted.width) }
        if refusedHeight { updated.height = max(current.height, accepted.height) }
        guard updated != current else { return false }
        rules.learnedMinimums[app] = updated
        return true
    }

    private func center(_ id: WindowID, context: TilingContext) {
        guard let frame = ax.currentFrame(of: id), let key = state.key(of: id),
            let area = state.area(of: key, context: context)
        else { return }
        ax.move(id, to: CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
        ax.raise(id)
    }

    private func updateOverlays(context: TilingContext) {
        overlays.update(
            OverlayModel(
                settings: settings, state: state, context: context, focused: state.focused, noPeekOn: noPeekOn,
                frontFrames: { [ax] id in ax.record(id)?.frame }),
            controller: self)
    }

    // MARK: Notices

    func show(_ notices: [Notice]) {
        for notice in notices {
            switch notice {
            case .stacked:
                guard !settings.stackNoticeShown else { continue }
                settings.stackNoticeShown = true
                overlays.showNotice(String(localized: "This screen is full, so the window joined this tile's stack."))
            case .spaceFull:
                overlays.showNotice(String(localized: "This Space is full"))
            case .maximumSize:
                overlays.showNotice(String(localized: "Maximum size reached"))
                NSSound.beep()
            case .minimumSize:
                overlays.showNotice(String(localized: "Minimum size reached"))
                NSSound.beep()
            case .doesNotFit(let app):
                let name = NSWorkspace.shared.runningApplications
                    .first { $0.bundleIdentifier == app }?.localizedName ?? app
                overlays.showNotice(String(localized: "There isn't enough room for \(name) on that screen."))
            }
        }
    }

    // MARK: Shortcuts

    enum SettingsTab: Hashable {
        case general, layout, highlight, keyboard, apps, about
    }

    func perform(_ action: ShortcutAction) {
        guard isOperating else { return }
        if action == .tabView || action == .tabViewBackward {
            tabView.pressed(backward: action == .tabViewBackward)
            return
        }
        if let number = action.workspaceNumber {
            switchToWorkspace(number)
            return
        }
        if let number = action.moveWorkspaceNumber {
            moveFocusedWindow(toWorkspace: number)
            return
        }
        if let direction = action.focusDirection {
            // Tab View uses the same keys to move its selection while it is open.
            if tabView.isOpen {
                tabView.moveSelection(direction)
            } else if let id = shownFocusedWindow(),
                let target = state.focusTarget(from: id, direction: direction, context: context()) {
                showWindow(target)
            }
            return
        }
        let context = context()
        if let count = action.tileCount {
            guard let key = activeKey() else { return }
            setCount(count, on: key)
            return
        }
        switch action {
        case .noPeek:
            toggleNoPeek()
            return
        case .cleanSpace:
            toggleCleanSpace()
            return
        case .retile:
            retile()
            return
        case .resetSizes:
            guard let key = activeKey() else { return }
            resetSizes(on: key)
            return
        case .float, .alwaysFloat:
            floatCommand(always: action == .alwaysFloat)
            return
        default:
            break
        }

        // Everything else acts on a tiled window only.
        guard let id = shownFocusedWindow() else { return }
        switch action {
        case .swapLeft: show(state.moveOrSwap(id, direction: .left, context: context))
        case .swapRight: show(state.moveOrSwap(id, direction: .right, context: context))
        case .swapUp: show(state.moveOrSwap(id, direction: .up, context: context))
        case .swapDown: show(state.moveOrSwap(id, direction: .down, context: context))
        case .makePrimary: state.makePrimary(id, context: context)
        case .nextWindow, .previousWindow:
            if let next = state.adjacentWindow(to: id, forward: action == .nextWindow) { ax.focus(next) }
            return
        case .nextInTile, .previousInTile:
            if let next = state.cycleStack(of: id, forward: action == .nextInTile) {
                ax.focus(next)
                state.focused = next
            }
        case .bigger, .smaller:
            show(state.step(id, grow: action == .bigger, context: context))
            if let key = state.key(of: id) { saveScreenPreferences(key) }
        case .focus: state.toggleZoom(id, context: context)
        default: return
        }
        apply(context: context)
        for key in Set(context.screens.map(\.key)) { persistCount(key) }
    }

    private func persistCount(_ key: WorkspaceKey) {
        guard let workspace = state.workspaces[key] else { return }
        let stored = screens.screens[ScreensFile.id(key)]
        if stored?.count != workspace.count || stored?.kind != workspace.kind { saveScreenPreferences(key) }
    }

    private func floatCommand(always: Bool) {
        guard let id = ax.focusedWindow(), let record = ax.record(id) else { return }
        if always {
            if !rules.excluded.contains(record.bundleID) { rules.excluded.append(record.bundleID) }
            return
        }
        guard record.isTileable, !rules.excluded.contains(record.bundleID) else { return }
        state.toggleFloat(id, context: context())
        scheduleRefresh(pid: nil)
    }

    func retile() {
        lastApplied = [:]
        let moved = apply()
        overlays.showNotice(
            moved == 0
                ? String(localized: "Everything was already in place.")
                : String(localized: "Put \(moved) windows back in place."))
    }

    func setCount(_ count: Int, on key: WorkspaceKey) {
        hydrate(key)
        show(state.setCount(count, on: key, context: context()))
        saveScreenPreferences(key)
        apply()
    }

    func setKind(_ kind: LayoutKind, on key: WorkspaceKey) {
        hydrate(key)
        state.setKind(kind, on: key, context: context())
        saveScreenPreferences(key)
        apply()
    }

    func resetSizes(on key: WorkspaceKey) {
        state.resetSizes(on: key)
        saveScreenPreferences(key)
        apply()
    }

    func toggleNoPeek() {
        noPeekOn.toggle()
        apply()
    }

    func toggleCleanSpace(on chosen: WorkspaceKey? = nil) {
        guard let key = chosen ?? activeKey() else { return }
        hydrate(key)
        state.toggleClean(on: key, active: ax.focusedWindow().flatMap { state.key(of: $0) == key ? $0 : nil })
        lastApplied = [:]
        apply()
    }

    private func endCleanSpaces() {
        guard hasCleanSpace else { return }
        state.endClean()
        apply()
    }

    func toggleTile(for bundleID: String) {
        if rules.excluded.contains(bundleID) {
            rules.excluded.removeAll { $0 == bundleID }
        } else {
            rules.excluded.append(bundleID)
        }
    }

    // MARK: Lookups

    /// The focused window, unless it is untracked or parked: after switching to an empty workspace,
    /// macOS can keep reporting the window that was just hidden.
    func shownFocusedWindow() -> WindowID? {
        guard let id = ax.focusedWindow(), let key = state.key(of: id), isShown(key) else { return nil }
        return id
    }

    func activeKey() -> WorkspaceKey? {
        if let id = shownFocusedWindow(), let key = state.key(of: id) { return key }
        return pointerKey()
    }

    func pointerKey() -> WorkspaceKey? {
        let displays = Displays.current()
        guard let display = Displays.display(containing: Displays.pointerLocation(), in: displays) else { return nil }
        return visibleKey(display.uuid)
    }

    /// The tiled window on top at a point, using window bounds only.
    func tiledWindow(at point: CGPoint, tolerance: CGFloat = 0) -> WindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }
        for entry in list {
            guard let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds),
                rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point),
                let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let owner = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owner != getpid(),
                // Border and overlay utilities draw over windows without taking their clicks.
                NSRunningApplication(processIdentifier: owner)?.activationPolicy == .regular
            else { continue }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            // Menus, the Dock and other windows above the normal level take the point.
            if layer != 0 { return nil }
            guard let key = state.key(of: number), isShown(key) else { return nil }
            return number
        }
        return nil
    }

    /// The tile under a point on any active screen.
    func tile(at point: CGPoint, context: TilingContext) -> (key: WorkspaceKey, index: Int?)? {
        guard let screen = context.screens.first(where: { $0.area.contains(point) }) else { return nil }
        let frames = state.slotFrames(on: screen.key, context: context)
        return (screen.key, frames.firstIndex { $0.contains(point) })
    }

    // MARK: Dragging

    func dragHover(id: WindowID, pointer: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let context = context()
        guard let source = state.key(of: id), let target = tile(at: pointer, context: context) else {
            overlays.hideDropHighlight()
            return
        }
        let command = modifiers.contains(.command)
        let option = modifiers.contains(.option)
        let frames = state.slotFrames(on: target.key, context: context)
        if let index = target.index, frames.indices.contains(index) {
            let own = state.workspaces[target.key]?.tiles[safe: index]?.windows.contains(id) ?? false
            if own {
                overlays.hideDropHighlight()
            } else if command, option {
                overlays.showDropHighlight(frames[index], text: String(localized: "Add to stack"))
            } else if command {
                overlays.showDropHighlight(frames[index], text: String(localized: "Swap"))
            } else if target.key != source {
                overlays.showDropHighlight(frames[index], text: String(localized: "Move here"))
            } else {
                overlays.hideDropHighlight()
            }
        } else if target.key != source, let area = state.area(of: target.key, context: context) {
            overlays.showDropHighlight(area.insetBy(dx: 40, dy: 40), text: String(localized: "Move here"))
        } else {
            overlays.hideDropHighlight()
        }
    }

    func finishMove(id: WindowID, pointer: CGPoint, modifiers: NSEvent.ModifierFlags) {
        overlays.hideDropHighlight()
        let context = context()
        guard let source = state.key(of: id), let target = tile(at: pointer, context: context) else { return }
        let command = modifiers.contains(.command)
        let option = modifiers.contains(.option)
        let shown = target.index.flatMap { state.workspaces[target.key]?.tiles[safe: $0]?.windows.first }

        if command, option, let index = target.index {
            state.moveToTile(id, tile: index, on: target.key, context: context)
        } else if command, let shown {
            state.swap(id, with: shown, context: context)
        } else if target.key != source {
            hydrate(target.key)
            _ = state.join(id, to: target.key, context: context)
        }
        state.show(id)
        lastApplied[id] = nil
        saveScreenPreferences(target.key)
    }

    func finishResize(id: WindowID, frame: CGRect) {
        let context = context()
        // In Focus and Clean Space the window isn't in its slot, so the drag says nothing about the slot.
        guard let key = state.key(of: id), state.workspaces[key]?.zoomed == nil,
            state.workspaces[key]?.cleanSet == nil,
            let index = state.workspaces[key]?.tiles.firstIndex(where: { $0.windows.contains(id) }),
            let slot = state.slotFrames(on: key, context: context)[safe: index]
        else { return }
        let deltas = EdgeDeltas(
            minX: frame.minX - slot.minX, maxX: frame.maxX - slot.maxX,
            minY: frame.minY - slot.minY, maxY: frame.maxY - slot.maxY)
        if state.dragEdges(of: id, deltas: deltas, context: context) { saveScreenPreferences(key) }
        lastApplied[id] = nil
    }

    func dragEnded() {
        scheduleRefresh(pid: nil)
    }

    func dropChip(id: WindowID) {
        let context = context()
        guard let target = tile(at: Displays.pointerLocation(), context: context), let index = target.index else {
            overlays.hideDropHighlight()
            return
        }
        overlays.hideDropHighlight()
        state.moveToTile(id, tile: index, on: target.key, context: context)
        apply(context: context)
        ax.focus(id)
    }

    func chipDragHover(id: WindowID) {
        let context = context()
        guard let target = tile(at: Displays.pointerLocation(), context: context), let index = target.index,
            let frame = state.slotFrames(on: target.key, context: context)[safe: index],
            state.workspaces[target.key]?.tiles[index].windows.contains(id) == false
        else {
            overlays.hideDropHighlight()
            return
        }
        overlays.showDropHighlight(frame, text: String(localized: "Move here"))
    }

    func showWindow(_ id: WindowID) {
        // Tab View and chips can pick a window from a workspace that isn't showing.
        if let key = state.key(of: id), !isShown(key) {
            _ = workspaceMap.show(key.virtual, focusedDisplay: key.display, isEmpty: false)
            lastWorkspaceSwitch = Date()
            hydrate(visibleKey(key.display))
        }
        state.show(id)
        ax.focus(id)
        // Otherwise applying the plan re-raises the previous window and undoes the switch.
        state.focused = id
        apply()
    }

    /// Screens in the order of System Settings → Displays → Arrange, left to right.
    func orderedScreens() -> [(key: WorkspaceKey, name: String)] {
        Displays.current().sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }.map {
            (visibleKey($0.uuid), $0.name)
        }
    }

    func moveWindow(_ id: WindowID, to target: WorkspaceKey) {
        hydrate(target)
        show(state.moveToScreen(id, target: target, context: context()))
        apply()
    }

    func moveToNextScreen(_ id: WindowID) {
        let screens = orderedScreens()
        guard screens.count > 1, let key = state.key(of: id),
            let index = screens.firstIndex(where: { $0.key == key })
        else { return }
        moveWindow(id, to: screens[(index + 1) % screens.count].key)
    }

    func toggleFloatWindow(_ id: WindowID) {
        state.toggleFloat(id, context: context())
        scheduleRefresh(pid: nil)
    }

    func toggleZoomWindow(_ id: WindowID) {
        state.toggleZoom(id, context: context())
        apply()
    }

    func makePrimaryWindow(_ id: WindowID) {
        state.makePrimary(id, context: context())
        apply()
    }

    /// Largest window count this layout allows on this screen.
    func maxCount(kind: LayoutKind, on key: WorkspaceKey) -> Int {
        let context = context()
        guard let area = state.area(of: key, context: context) else { return 4 }
        return LayoutEngine.maxCount(kind: kind, area: area, gap: context.policy.gap)
    }

    func closeWindow(_ id: WindowID) {
        if !ax.close(id) {
            overlays.showNotice(String(localized: "This window has no close option."))
        }
    }
}
