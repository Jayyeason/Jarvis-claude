import AppKit
import SwiftUI

class APISettingsWindowManager {
    static let shared = APISettingsWindowManager()

    private var window: NSWindow?

    func open() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "配置云端 API"
        w.contentView = NSHostingView(rootView: APISettingsPanel())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
