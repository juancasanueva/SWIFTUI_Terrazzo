import ServiceManagement

/// What to ask macOS for so the login item matches the "Open at login" setting.
enum LoginItemChange: Equatable {
    case register
    case unregister

    /// Nil when macOS already agrees: registering twice and unregistering twice both fail.
    static func needed(openAtLogin: Bool, status: SMAppService.Status) -> LoginItemChange? {
        if openAtLogin { return status == .enabled ? nil : .register }
        switch status {
        case .notRegistered, .notFound: return nil
        case .enabled, .requiresApproval: return .unregister
        @unknown default: return .unregister
        }
    }
}
