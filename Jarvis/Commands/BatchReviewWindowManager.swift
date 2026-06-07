import AppKit
import SwiftUI

@MainActor
class BatchReviewWindowManager {
    static let shared = BatchReviewWindowManager()

    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?
    private var isClosing = false
    private let windowSize = NSSize(width: 440, height: 460)

    func open(response: AgentResponse, onCandidateResolved: ((BatchReviewResult) -> Void)? = nil) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = BatchReviewPanel(
            response: response,
            onCandidateResolved: onCandidateResolved,
            onClose: { [weak self] in self?.close() }
        )
        let window = KeyableBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "确认日程与待办"
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
            self?.isClosing = false
        }
        windowDelegate = delegate
        window.delegate = delegate
        self.window = window
        let finalFrame = frameForRightDock(size: windowSize)
        let startFrame = finalFrame.offsetBy(dx: 32, dy: -4)
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
    }

    func close() {
        guard let window, !isClosing else { return }
        isClosing = true
        let exitFrame = window.frame.offsetBy(dx: 28, dy: -6)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(exitFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                window?.close()
                self?.window = nil
                self?.windowDelegate = nil
                self?.isClosing = false
            }
        }
    }

    private func frameForRightDock(size: NSSize) -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 18
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - 24
        return NSRect(
            x: max(visible.minX + margin, x),
            y: max(visible.minY + margin, y),
            width: size.width,
            height: min(size.height, visible.height - margin * 2)
        )
    }

    private class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }

    private class KeyableBorderlessWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
