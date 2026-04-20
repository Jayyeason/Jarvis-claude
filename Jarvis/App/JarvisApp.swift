import SwiftUI
import AppKit

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    private var globalHotkey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GatewayManager.shared.start()
        statusBarController = StatusBarController()
        registerGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GatewayManager.shared.stop()
        if let monitor = globalHotkey {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func registerGlobalHotkey() {
        // Prompt for accessibility permission if not granted
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        jlog("[Hotkey] Accessibility trusted: \(trusted)")
        guard trusted else {
            jlog("[Hotkey] No accessibility permission — global hotkey disabled")
            return
        }
        globalHotkey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 38 {
                Task { @MainActor in CaptureManager.shared.capture() }
            }
        }
        jlog("[Hotkey] Global hotkey ⌘⇧J registered")
    }
}
