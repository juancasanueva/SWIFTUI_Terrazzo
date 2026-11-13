/// The order to raise Clean Space windows in, bottom to top, so they all stand above the background.
enum CleanSpaceOrder {
    /// Raising can take the keyboard within an app, so the focused window goes last and keeps it.
    static func raising(_ clean: [WindowID], focused: WindowID?) -> [WindowID] {
        guard let focused, clean.contains(focused) else { return clean }
        return clean.filter { $0 != focused } + [focused]
    }
}
