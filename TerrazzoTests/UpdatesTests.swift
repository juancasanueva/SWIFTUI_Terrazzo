import Foundation
import Observation
import Testing
@testable import Terrazzo

@Observable
private final class FakeAppUpdater: AppUpdating {
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    var automaticWrites: [Bool] = []
    var checkCount = 0

    var automaticallyChecksForUpdates = false {
        didSet { automaticWrites.append(automaticallyChecksForUpdates) }
    }

    func checkForUpdates() { checkCount += 1 }
}

@MainActor
struct AutomaticUpdateChecksTests {
    private func settingsFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("settings.json")
    }

    @Test func aFreshInstallDoesNotCheckAutomatically() {
        #expect(!AppSettings().automaticUpdateChecks)
    }

    @Test func aSettingsFileFromBeforeThisKeyStaysOff() throws {
        let url = try settingsFile()
        try Data(#"{"gap": 20}"#.utf8).write(to: url)
        let settings = try ConfigFile(url: url, defaults: AppSettings()).load()
        #expect(settings.gap == 20)
        #expect(!settings.automaticUpdateChecks)
    }

    @Test func theAnswerPersistsInTheSettingsFile() throws {
        let file = ConfigFile(url: try settingsFile(), defaults: AppSettings())
        var settings = AppSettings()
        settings.automaticUpdateChecks = true
        try file.save(settings)
        #expect(try file.load().automaticUpdateChecks)
    }

    @Test(arguments: [true, false])
    func aChangedPreferenceReachesTheUpdaterOnce(preference: Bool) {
        let updater = FakeAppUpdater()
        var old = AppSettings()
        old.automaticUpdateChecks = !preference
        var new = AppSettings()
        new.automaticUpdateChecks = preference
        new.applyUpdatePreference(changedFrom: old, to: updater)
        #expect(updater.automaticWrites == [preference])
        #expect(updater.checkCount == 0)
    }

    @Test func anotherSettingChangingLeavesTheUpdaterAlone() {
        let updater = FakeAppUpdater()
        var new = AppSettings()
        new.gap = 20
        new.applyUpdatePreference(changedFrom: AppSettings(), to: updater)
        #expect(updater.automaticWrites.isEmpty)
    }
}

@MainActor
struct UpdateCommandTests {
    @Test func untilTheAppStartsNoCheckCanRun() {
        let updater = NoUpdater()
        #expect(!updater.canCheckForUpdates)
        #expect(updater.lastUpdateCheckDate == nil)
    }

    @Test func theControllerHasNoRealUpdaterBeforeItStarts() {
        #expect(AppController.shared.updater is NoUpdater)
    }

    @Test(arguments: [true, false])
    func theButtonFollowsWhetherACheckCanRun(canCheck: Bool) {
        let updater = FakeAppUpdater()
        updater.canCheckForUpdates = canCheck
        #expect(CheckForUpdatesButton(updater: updater).isDisabled == !canCheck)
    }
}

struct UpdateCheckPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aBundleThatNeverCheckedSaysSo() {
        #expect(UpdateCheckPresentation(lastCheck: nil, now: now).label == String(localized: "Never checked"))
    }

    @Test(arguments: [("en_US", "2 hours ago"), ("es_ES", "hace 2 horas")])
    func aPastCheckReadsRelativeToNow(locale: String, expected: String) {
        let lastCheck = now.addingTimeInterval(-2 * 3600)
        let label = UpdateCheckPresentation(lastCheck: lastCheck, now: now, locale: Locale(identifier: locale)).label
        #expect(label.contains(expected))
    }
}
