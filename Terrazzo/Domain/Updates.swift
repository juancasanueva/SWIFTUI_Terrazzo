import Foundation
import Observation

/// Everything the app asks of an updater. `SparkleUpdateChecker` is the adapter; the interface only
/// sees this, and tests drive it with a fake.
///
/// `AnyObject` so every surface observes the same instance; `Observable` so a view holding
/// `any AppUpdating` still re-renders.
@MainActor
protocol AppUpdating: AnyObject, Observable {
    /// False while a check is already running.
    var canCheckForUpdates: Bool { get }
    /// Whether the updater checks on its own. `AppSettings.automaticUpdateChecks` decides it.
    var automaticallyChecksForUpdates: Bool { get set }
    /// When the last check completed, or `nil` if there has never been one.
    var lastUpdateCheckDate: Date? { get }
    /// Starts exactly one check.
    func checkForUpdates()
}

/// Stands in until `AppController.start()`, so the command line and unit tests never start an updater.
@Observable
final class NoUpdater: AppUpdating {
    let canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    let lastUpdateCheckDate: Date? = nil

    func checkForUpdates() {}
}

extension AppSettings {
    /// Passes the preference on only when it changed, whether in Settings or in `settings.json`.
    func applyUpdatePreference(changedFrom old: AppSettings, to updater: any AppUpdating) {
        guard old.automaticUpdateChecks != automaticUpdateChecks else { return }
        updater.automaticallyChecksForUpdates = automaticUpdateChecks
    }
}

/// "Last checked …" in Settings. `now` is injected so the label is a pure function of its inputs.
struct UpdateCheckPresentation {
    let lastCheck: Date?
    let now: Date
    var locale: Locale = .current

    var label: String {
        guard let lastCheck else { return String(localized: "Never checked") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return String(localized: "Last checked \(formatter.localizedString(for: lastCheck, relativeTo: now))")
    }
}
