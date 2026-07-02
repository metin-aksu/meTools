import SwiftUI

@main
struct meToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app: the settings window is managed by AppDelegate,
        // opened from the status-item menu. Settings-with-EmptyView keeps
        // SwiftUI from creating any window of its own.
        Settings {
            EmptyView()
        }
    }
}
