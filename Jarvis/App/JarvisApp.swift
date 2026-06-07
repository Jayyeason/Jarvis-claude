import SwiftUI
import AppKit

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Jarvis") {
            JarvisMainView()
        }
        .commands {
            JarvisCommands()
        }

        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalHotkey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        jlog("[App] Launching Jarvis. Logs: \(jlogPathDescription())")
        NSApp.setActivationPolicy(.regular)
        GatewayManager.shared.start()

        // Island window
        let island = IslandWindowController.shared
        island.onCaptureRequested = { CaptureManager.shared.capture() }
        island.onSettingsRequested = { APISettingsWindowManager.shared.open() }
        island.onTaskListRequested = {
            let anchorRect = IslandWindowController.shared.currentPanelFrame
            TaskListWindowManager.shared.toggle(anchorRect: anchorRect)
        }
        island.setup()

        // Wire capture callbacks
        CaptureManager.shared.onCaptureStart = {
            Task { @MainActor in IslandWindowController.shared.showCapturing() }
        }
        CaptureManager.shared.onCaptureComplete = { response in
            Task { @MainActor in
                IslandWindowController.shared.showAgentResponse(response)
            }
        }
        CaptureManager.shared.onCaptureError = { _ in
            Task { @MainActor in IslandWindowController.shared.restoreIdle() }
        }

        HeartbeatManager.shared.start()
        registerGlobalHotkey()
        activateMainWindowSoon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GatewayManager.shared.stop()
        HeartbeatManager.shared.stop()
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

    private func activateMainWindowSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            jlog("[App] Activated Jarvis main window")
        }
    }
}
