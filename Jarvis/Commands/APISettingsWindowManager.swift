import AppKit
import SwiftUI

@MainActor
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
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: APISettingsPanel())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

@MainActor
class ModelManagerWindowManager {
    static let shared = ModelManagerWindowManager()

    private var window: NSWindow?

    func open() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "管理端侧模型"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: ModelManagerPanel())
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
