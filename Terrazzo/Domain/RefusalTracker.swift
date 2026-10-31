import CoreGraphics
import Foundation

/// Decides when a window not taking the size it was given means the app has a minimum size.
/// A slow or busy app looks the same at first: its window just hasn't resized yet.
struct RefusalTracker {
    enum Verdict: Equatable {
        case none
        case checkAgain(after: TimeInterval)
        /// The size to remember; zero on an axis that wasn't refused.
        case learn(CGSize)
    }

    private struct Sighting {
        var accepted: CGSize
        var firstSeen: Date
        /// The app moved the window to this size itself, which a slow app wouldn't have done.
        var clamped: Bool
    }

    /// Small differences are grid rounding, as in terminals.
    static let tolerance: CGFloat = 24
    static let quickRetry: TimeInterval = 0.3
    static let slowRetry: TimeInterval = 1
    /// How long a window that doesn't move must keep refusing before it counts.
    static let patience: TimeInterval = 2.5
    /// No app needs this much of the screen as a minimum. Such a reading is a window not yet resized.
    static let implausibleShare: CGFloat = 0.9

    private var sightings: [WindowID: Sighting] = [:]

    mutating func note(
        id: WindowID, requested: CGRect, accepted: CGRect, previous: CGRect, area: CGRect, now: Date
    ) -> Verdict {
        let refusedWidth = accepted.width > requested.width + Self.tolerance
        let refusedHeight = accepted.height > requested.height + Self.tolerance
        let implausible =
            (refusedWidth && accepted.width >= area.width * Self.implausibleShare)
            || (refusedHeight && accepted.height >= area.height * Self.implausibleShare)
        guard refusedWidth || refusedHeight, !implausible else {
            sightings[id] = nil
            return .none
        }
        let size = CGSize(width: refusedWidth ? accepted.width : 0, height: refusedHeight ? accepted.height : 0)

        if let seen = sightings[id], abs(seen.accepted.width - accepted.width) < 2,
            abs(seen.accepted.height - accepted.height) < 2 {
            if seen.clamped || now.timeIntervalSince(seen.firstSeen) >= Self.patience {
                sightings[id] = nil
                return .learn(size)
            }
            return .checkAgain(after: Self.slowRetry)
        }

        let moved = abs(accepted.width - previous.width) >= 2 || abs(accepted.height - previous.height) >= 2
        sightings[id] = Sighting(accepted: accepted.size, firstSeen: now, clamped: moved)
        return .checkAgain(after: moved ? Self.quickRetry : Self.slowRetry)
    }
}
