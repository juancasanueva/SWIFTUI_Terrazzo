import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.saveLayoutNow()
        AppController.shared.revealHiddenWindows()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; they must not touch real windows or shortcuts.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = AppController.shared
        controller.start()
        if !controller.settings.setupFinished {
            TourWindow.show(controller: controller)
        }
    }
}

@main
enum Entry {
    static func main() {
        guard !TilingCommandLine.runIfCommand() else { return }
        TilingApp.main()
    }
}

struct TilingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(controller: controller)
        } label: {
            MenuBarIcon(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: controller)
        }
    }
}
