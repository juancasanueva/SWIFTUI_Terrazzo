import AppKit
import Carbon.HIToolbox

/// Registers global shortcuts with the system. The app only learns when its own combinations are pressed.
final class HotKeyCenter {
    private var references: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var handler: EventHandlerRef?
    private var temporaryReferences: [EventHotKeyRef] = []
    private var temporaryKeys: [UInt32: ShortcutKey] = [:]
    private var onTemporaryPress: ((ShortcutKey) -> Void)?
    var onPress: ((ShortcutAction) -> Void)?

    /// Claims keys only while something like Tab View is open, without taking keyboard focus from the
    /// active app. Numbered apart from regular shortcuts.
    func registerTemporary(
        _ keys: [ShortcutKey], modifiers: KeyModifiers, onPress: @escaping (ShortcutKey) -> Void
    ) {
        unregisterTemporary()
        installHandlerIfNeeded()
        onTemporaryPress = onPress
        for (index, key) in keys.enumerated() {
            let id = UInt32(index + 1000)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                key.keyCode, Self.carbonModifiers(modifiers), EventHotKeyID(signature: OSType(0x544C_4E47), id: id),
                GetEventDispatcherTarget(), 0, &reference)
            if status == noErr, let reference {
                temporaryReferences.append(reference)
                temporaryKeys[id] = key
            }
        }
    }

    func unregisterTemporary() {
        temporaryReferences.forEach { UnregisterEventHotKey($0) }
        temporaryReferences = []
        temporaryKeys = [:]
        onTemporaryPress = nil
    }

    /// Returns the actions the system refused.
    @discardableResult
    func register(_ combos: [ShortcutAction: KeyCombo]) -> [ShortcutAction] {
        unregisterAll()
        installHandlerIfNeeded()
        var failed: [ShortcutAction] = []
        for (index, entry) in combos.enumerated() {
            let id = UInt32(index + 1)
            let hotKeyID = EventHotKeyID(signature: OSType(0x544C_4E47), id: id)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                entry.value.key.keyCode, Self.carbonModifiers(entry.value.modifiers), hotKeyID,
                GetEventDispatcherTarget(), 0, &reference)
            if status == noErr, let reference {
                references.append(reference)
                actions[id] = entry.key
            } else {
                failed.append(entry.key)
            }
        }
        return failed
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references = []
        actions = [:]
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyEventCallback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(),
            &handler)
    }

    fileprivate func pressed(id: UInt32) {
        if let key = temporaryKeys[id] {
            onTemporaryPress?(key)
        } else if let action = actions[id] {
            onPress?(action)
        }
    }

    static func carbonModifiers(_ modifiers: KeyModifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    /// Shortcuts macOS itself has claimed, from System Settings → Keyboard → Keyboard Shortcuts.
    static func systemShortcuts() -> Set<KeyCombo> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let list = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var result: Set<KeyCombo> = []
        for entry in list {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                let code = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                let raw = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.intValue,
                let key = ShortcutKey(keyCode: code)
            else { continue }
            var modifiers: KeyModifiers = []
            if raw & controlKey != 0 { modifiers.insert(.control) }
            if raw & optionKey != 0 { modifiers.insert(.option) }
            if raw & shiftKey != 0 { modifiers.insert(.shift) }
            if raw & cmdKey != 0 { modifiers.insert(.command) }
            result.insert(KeyCombo(key: key, modifiers: modifiers))
        }
        return result
    }
}

private nonisolated func hotKeyEventCallback(
    _ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        let center = Unmanaged<HotKeyCenter>
            .fromOpaque(UnsafeRawPointer(bitPattern: address)!).takeUnretainedValue()
        center.pressed(id: id)
    }
    return noErr
}
