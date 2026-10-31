/// Decides when the focused window has to be raised. Raising it puts it above its own border until the border
/// is ordered again, so a window that is already on top is left alone.
struct FocusRaiseTracker {
    private var lastFocused: WindowID?

    /// `othersRaised` says another window was raised just before, which may have covered the focused one.
    mutating func shouldRaise(focused: WindowID?, othersRaised: Bool) -> Bool {
        defer { lastFocused = focused }
        guard let focused else { return false }
        return focused != lastFocused || othersRaised
    }
}
