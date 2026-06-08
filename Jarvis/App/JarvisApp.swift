import SwiftUI
import AppKit
import Carbon

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
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private static let captureHotKeyID = UInt32(1)
    private static let hotKeySignature = fourCharCode("JARV")

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
        island.onAssistantChatRequested = {
            let anchorRect = IslandWindowController.shared.currentPanelFrame
            AssistantChatWindowManager.shared.toggle(anchorRect: anchorRect)
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
        unregisterGlobalHotkey()
    }

    private func registerGlobalHotkey() {
        unregisterGlobalHotkey()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr,
                      hotKeyID.signature == AppDelegate.hotKeySignature,
                      hotKeyID.id == AppDelegate.captureHotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }

                jlog("[Hotkey] ⌘⇧J pressed")
                Task { @MainActor in CaptureManager.shared.capture() }
                return noErr
            },
            1,
            &eventType,
            nil,
            &hotKeyHandler
        )
        guard handlerStatus == noErr else {
            jlog("[Hotkey] Failed to install Carbon hotkey handler status=\(handlerStatus)")
            return
        }

        var hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.captureHotKeyID
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_J),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            jlog("[Hotkey] Failed to register ⌘⇧J status=\(registerStatus)")
            unregisterGlobalHotkey()
            return
        }
        jlog("[Hotkey] Carbon hotkey ⌘⇧J registered without Accessibility permission")
    }

    private func unregisterGlobalHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
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

    private static func fourCharCode(_ value: String) -> OSType {
        value.utf8.prefix(4).reduce(0) { result, byte in
            (result << 8) + OSType(byte)
        }
    }
}
