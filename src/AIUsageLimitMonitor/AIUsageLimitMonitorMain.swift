import SwiftUI

@main
struct AIUsageLimitMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}
