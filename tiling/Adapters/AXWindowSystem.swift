import AppKit
import ApplicationServices

/// Maps an Accessibility element to its window number. Long-standing, no public equivalent.
@_silgen_name("_AXUIElementGetWindow")
private func axElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowRecord {
    var id: WindowID
    var element: AXUIElement
    var pid: pid_t
    var bundleID: String
    var appName: String
    var frame: CGRect
    var isMinimized: Bool
    /// False for windows that may be shown but must never be tiled.
    var isTileable: Bool
}

/// Reads and moves other apps' windows through Accessibility. Reads position, size and owning app;
/// titles are read only on request and never kept.
final class AXWindowSystem {
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: Set<WindowID> = []
    private var cache: [pid_t: [WindowRecord]] = [:]
    /// Called on the main thread with the app whose windows changed.
    var onChange: ((pid_t) -> Void)?

    private static let messagingTimeout: Float = 0.25

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func eligibleApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }
    }

    // MARK: Scanning

    /// Rescans one app, or every eligible app when `pid` is nil, and returns all known windows.
    func scan(pid: pid_t?) -> [WindowRecord] {
        let apps = Self.eligibleApps()
        let alive = Set(apps.map(\.processIdentifier))
        cache = cache.filter { alive.contains($0.key) }
        for (stale, _) in observers where !alive.contains(stale) { observers[stale] = nil }

        for app in apps where pid == nil || app.processIdentifier == pid || cache[app.processIdentifier] == nil {
            observe(app)
            cache[app.processIdentifier] = app.isHidden ? [] : records(of: app)
        }
        return cache.values.flatMap { $0 }
    }

    func forgetAll() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers = [:]
        observedWindows = []
        cache = [:]
    }

    private func records(of app: NSRunningApplication) -> [WindowRecord] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        guard let windows: [AXUIElement] = Self.attribute(element, kAXWindowsAttribute) else { return [] }
        let bundleID = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
        let appName = app.localizedName ?? bundleID
        return windows.compactMap { window in
            // A hung app must not stall the main thread for long.
            AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)
            var id: CGWindowID = 0
            guard axElementGetWindow(window, &id) == .success, id != 0 else { return nil }
            guard let frame = Self.frame(of: window) else { return nil }
            let isMinimized = (Self.attribute(window, kAXMinimizedAttribute) as Bool?) ?? false
            observeDestruction(of: window, id: id, pid: app.processIdentifier)
            return WindowRecord(
                id: id, element: window, pid: app.processIdentifier, bundleID: bundleID, appName: appName,
                frame: frame, isMinimized: isMinimized, isTileable: Self.isStandard(window))
        }
    }

    /// A standard window: title bar, the three buttons, resizable, not full-screen.
    private static func isStandard(_ window: AXUIElement) -> Bool {
        guard (attribute(window, kAXRoleAttribute) as String?) == kAXWindowRole,
            (attribute(window, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole,
            (attribute(window, "AXFullScreen") as Bool?) != true,
            (attribute(window, kAXCloseButtonAttribute) as AXUIElement?) != nil,
            (attribute(window, kAXMinimizeButtonAttribute) as AXUIElement?) != nil,
            (attribute(window, kAXZoomButtonAttribute) as AXUIElement?) != nil
        else { return false }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        return settable.boolValue
    }

    func focusedWindow() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        guard let window: AXUIElement = Self.attribute(element, kAXFocusedWindowAttribute) else { return nil }
        var id: CGWindowID = 0
        return axElementGetWindow(window, &id) == .success ? id : nil
    }

    func title(of id: WindowID) -> String {
        guard let record = record(id) else { return "" }
        return (Self.attribute(record.element, kAXTitleAttribute) as String?) ?? ""
    }

    func record(_ id: WindowID) -> WindowRecord? {
        for records in cache.values {
            if let match = records.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    func currentFrame(of id: WindowID) -> CGRect? {
        record(id).flatMap { Self.frame(of: $0.element) }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(window, kAXPositionAttribute),
            let size: AXValue = attribute(window, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    // MARK: Acting

    /// Moves and resizes a window and returns the frame the app accepted.
    @discardableResult
    func setFrame(_ id: WindowID, to frame: CGRect) -> CGRect? {
        guard let record = record(id) else { return nil }
        let window = record.element
        // Some apps animate every change while this flag is on, and fall behind.
        let app = AXUIElementCreateApplication(record.pid)
        let enhanced = (Self.attribute(app, "AXEnhancedUserInterface") as Bool?) == true
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        // Position, size, position: a window near a screen edge may refuse a size until it has moved.
        setPosition(window, frame.origin)
        setSize(window, frame.size)
        setPosition(window, frame.origin)
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        return Self.frame(of: window)
    }

    func move(_ id: WindowID, to origin: CGPoint) {
        guard let record = record(id) else { return }
        setPosition(record.element, origin)
    }

    private func setPosition(_ window: AXUIElement, _ origin: CGPoint) {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func setSize(_ window: AXUIElement, _ size: CGSize) {
        var extent = size
        guard let value = AXValueCreate(.cgSize, &extent) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    func raise(_ id: WindowID) {
        guard let record = record(id) else { return }
        AXUIElementPerformAction(record.element, kAXRaiseAction as CFString)
    }

    func focus(_ id: WindowID) {
        guard let record = record(id) else { return }
        if record.isMinimized {
            AXUIElementSetAttributeValue(record.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let app = AXUIElementCreateApplication(record.pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(record.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, record.element)
        AXUIElementPerformAction(record.element, kAXRaiseAction as CFString)
    }

    /// Presses the window's close button, so unsaved work triggers the app's normal prompt.
    func close(_ id: WindowID) -> Bool {
        guard let record = record(id),
            let button: AXUIElement = Self.attribute(record.element, kAXCloseButtonAttribute)
        else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    // MARK: Observing

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
    ]

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axNotificationCallback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var failures = 0
        for name in Self.appNotifications {
            if AXObserverAddNotification(observer, element, name as CFString, context) != .success { failures += 1 }
        }
        // An app still launching refuses everything. Leaving it unstored means the next scan tries again.
        guard failures < Self.appNotifications.count else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func observeDestruction(of window: AXUIElement, id: WindowID, pid: pid_t) {
        guard let observer = observers[pid], observedWindows.insert(id).inserted else { return }
        AXObserverAddNotification(
            observer, window, kAXUIElementDestroyedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func notificationArrived(_ element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        onChange?(pid)
    }
}

private nonisolated func axNotificationCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let box = UncheckedBox(element: element, context: context)
    MainActor.assumeIsolated {
        Unmanaged<AXWindowSystem>.fromOpaque(box.context).takeUnretainedValue().notificationArrived(box.element)
    }
}

private struct UncheckedBox: @unchecked Sendable {
    let element: AXUIElement
    let context: UnsafeMutableRawPointer
}
