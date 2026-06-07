import AppKit
import SwiftUI

extension Notification.Name {
    static let jarvisAssistantChatAppendMessage = Notification.Name("jarvisAssistantChatAppendMessage")
}

@MainActor
class AssistantChatWindowManager {
    static let shared = AssistantChatWindowManager()

    private var window: NSWindow?
    private let windowSize = NSSize(width: 420, height: 520)

    func toggle(anchorRect: NSRect) {
        if let window, window.isVisible {
            close()
        } else {
            open(anchorRect: anchorRect)
        }
    }

    func open(anchorRect: NSRect) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = AssistantChatPanel(onClose: { [weak self] in
            self?.close()
        })

        let window = KeyableBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Jarvis 对话"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: content)
        self.window = window

        let finalFrame = frame(anchorRect: anchorRect, size: windowSize)
        let startFrame = finalFrame.offsetBy(dx: 0, dy: 18)
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1.0)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
    }

    func close() {
        guard let window else { return }
        let exitFrame = window.frame.offsetBy(dx: 0, dy: 12)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(exitFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                window?.close()
                self?.window = nil
            }
        }
    }

    func appendAssistantMessage(_ text: String) {
        NotificationCenter.default.post(name: .jarvisAssistantChatAppendMessage, object: text)
    }

    private func frame(anchorRect: NSRect, size: NSSize) -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8
        let margin: CGFloat = 12
        let x = min(max(anchorRect.midX - size.width / 2, visible.minX + margin), visible.maxX - size.width - margin)
        let preferredY = anchorRect.minY - size.height - gap
        let y = max(visible.minY + margin, preferredY)
        return NSRect(x: x, y: y, width: size.width, height: min(size.height, visible.height - margin * 2))
    }

    private class KeyableBorderlessWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
