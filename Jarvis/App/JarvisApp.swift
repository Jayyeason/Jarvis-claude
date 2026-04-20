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
    private var globalHotkey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GatewayManager.shared.start()

        // Island window
        let island = IslandWindowController.shared
        island.onCaptureRequested = { CaptureManager.shared.capture() }
        island.onSettingsRequested = { APISettingsWindowManager.shared.open() }
        island.setup()

        // Wire capture callbacks
        CaptureManager.shared.onCaptureStart = {
            Task { @MainActor in IslandWindowController.shared.showCapturing() }
        }
        CaptureManager.shared.onCaptureComplete = { response in
            Task { @MainActor in
                let result = RecognitionResult.from(response)
                IslandWindowController.shared.restoreIdle()
                guard result.eventType != nil else { return }
                IslandWindowController.shared.showConfirmationCard(
                    result: result,
                    onDismiss: {},
                    onSuccess: { IslandWindowController.shared.showSuccess() }
                )
            }
        }
        CaptureManager.shared.onCaptureError = { _ in
            Task { @MainActor in IslandWindowController.shared.restoreIdle() }
        }

        registerGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GatewayManager.shared.stop()
        if let monitor = globalHotkey {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func registerGlobalHotkey() {
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
