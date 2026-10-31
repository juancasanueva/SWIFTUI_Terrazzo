import AppKit
import Foundation
import Observation
import Sparkle

/// `AppUpdating` backed by Sparkle, and the only file that imports it. The feed URL and the EdDSA
/// public key come from `Resources/Terrazzo-Info.plist` and cannot be changed at run time.
@Observable
final class SparkleUpdateChecker: AppUpdating {
    private(set) var canCheckForUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastCheckObservation: NSKeyValueObservation?

    /// Applies the preference before starting the updater, so Sparkle never asks on its own whether
    /// to check automatically.
    init(automaticChecks: Bool) {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate

        controller.updater.automaticallyChecksForUpdates = automaticChecks
        controller.startUpdater()
        observeUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Terrazzo has no Dock icon and is rarely active, so it comes forward for Sparkle's window.
    func checkForUpdates() {
        NSApp.activate()
        controller.updater.checkForUpdates()
    }

    /// Sparkle changes both values on the main thread, so `assumeIsolated` holds.
    private func observeUpdater() {
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
        lastCheckObservation = controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastUpdateCheckDate = self.controller.updater.lastUpdateCheckDate
            }
        }
    }
}
