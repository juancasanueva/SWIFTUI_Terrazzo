/// Whether a window can be tiled, read through Accessibility one check at a time. A busy app, often one a
/// click just brought forward, may not answer a check in time.
enum WindowClassification {
    /// Runs the checks in order: false once one rules the window out, nil when one went unanswered.
    static func combine(_ checks: [() -> Bool?]) -> Bool? {
        var unanswered = false
        for check in checks {
            switch check() {
            case false?: return false
            case nil: unanswered = true
            case true?: continue
            }
        }
        return unanswered ? nil : true
    }

    /// An unanswered read keeps what was known. Dropping a tiled window would bring it back as a new one,
    /// and a new window of the frontmost app joins the workspace in use, which may be on another display.
    /// A window never read is not tiled until it answers.
    static func isTileable(read: Bool?, known: Bool?) -> Bool {
        read ?? known ?? false
    }
}
