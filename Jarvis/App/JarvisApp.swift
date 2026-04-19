import SwiftUI
import AppKit

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                JarvisCommands()
            }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        GatewayManager.shared.start()

        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GatewayManager.shared.stop()
    }
}
