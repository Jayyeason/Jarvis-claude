import AppKit
import SwiftUI

@MainActor
class TaskListWindowManager {
    static let shared = TaskListWindowManager()

    private var window: NSWindow?

    /// anchorRect: the island panel's frame in screen coordinates
    func toggle(anchorRect: NSRect) {
        if let w = window, w.isVisible {
            w.orderOut(nil)
            return
        }
        show(anchorRect: anchorRect)
    }

    private func show(anchorRect: NSRect) {
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 420
        let gap: CGFloat = 8

        let x = anchorRect.midX - panelWidth / 2
        let y = anchorRect.minY - panelHeight - gap

        let w = NSWindow(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hosting = NSHostingView(rootView: TaskListPanel())
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
        w.contentView = hosting

        // Dismiss when clicking outside
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak w] _ in
            guard let self, let w, w.isVisible else { return }
            DispatchQueue.main.async { w.orderOut(nil); self.window = nil }
        }

        w.makeKeyAndOrderFront(nil)
        self.window = w

        // Animate in
        w.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            w.animator().alphaValue = 1
        }
    }
}
