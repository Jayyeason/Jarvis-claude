import AppKit
import SwiftUI

/// Manages the always-on-top black capsule window at the top-center of the screen.
@MainActor
class IslandWindowController {
    static let shared = IslandWindowController()

    private var panel: NSPanel?
    private var confirmationPanel: NSPanel?
    private var trackingView: IslandTrackingView?

    private let collapsedSize = NSSize(width: 120, height: 32)
    private let expandedSize  = NSSize(width: 340, height: 44)

    private(set) var isExpanded = false
    private(set) var isCapturing = false

    var onCaptureRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?

    func setup() {
        let panel = makePanel(size: collapsedSize)
        self.panel = panel

        let tv = IslandTrackingView(frame: NSRect(origin: .zero, size: collapsedSize))
        tv.controller = self
        panel.contentView = tv
        trackingView = tv

        updateContent()
        positionPanel(size: collapsedSize)
        panel.orderFrontRegardless()
    }

    // MARK: - State transitions

    func showCapturing() {
        isCapturing = true
        updateContent()
        animateSize(to: NSSize(width: 160, height: 32))
    }

    func showSuccess() {
        isCapturing = false
        updateContent()
        animateSize(to: NSSize(width: 120, height: 32))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.restoreIdle()
        }
    }

    func restoreIdle() {
        isCapturing = false
        if isExpanded { collapse() } else { updateContent() }
    }

    func showConfirmationCard(result: RecognitionResult,
                              onDismiss: @escaping () -> Void,
                              onSuccess: @escaping () -> Void) {
        confirmationPanel?.close()

        let vc = NSHostingController(rootView: ConfirmationCard(
            result: result,
            onDismiss: { [weak self] in
                self?.confirmationPanel?.close()
                self?.confirmationPanel = nil
                onDismiss()
            },
            onSuccess: { [weak self] in
                self?.confirmationPanel?.close()
                self?.confirmationPanel = nil
                onSuccess()
            }
        ))
        vc.view.setFrameSize(NSSize(width: 300, height: 600))
        vc.view.layoutSubtreeIfNeeded()
        let h = vc.view.fittingSize.height
        let cardSize = NSSize(width: 300, height: h > 50 ? h : 280)
        vc.preferredContentSize = cardSize

        let cp = makePanel(size: cardSize)
        cp.contentViewController = vc
        confirmationPanel = cp

        positionBelow(panel: cp, size: cardSize)
        cp.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Hover

    func handleMouseEntered() {
        guard !isCapturing else { return }
        expand()
    }

    func handleMouseExited() {
        guard !isCapturing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isCapturing else { return }
            if let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
    }

    // MARK: - Private

    private func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        updateContent()
        animateSize(to: expandedSize)
    }

    private func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        updateContent()
        animateSize(to: collapsedSize)
    }

    private func updateContent() {
        guard let tv = trackingView else { return }
        let view = IslandCapsuleView(
            isExpanded: isExpanded,
            isCapturing: isCapturing,
            onCapture: { [weak self] in self?.onCaptureRequested?() },
            onSettings: { [weak self] in self?.onSettingsRequested?() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        tv.subviews.forEach { $0.removeFromSuperview() }
        hosting.frame = tv.bounds
        tv.addSubview(hosting)
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        return p
    }

    private func positionPanel(size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height - 6
        panel?.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    private func positionBelow(panel cp: NSPanel, size: NSSize) {
        guard let mainPanel = panel, let screen = NSScreen.main else { return }
        _ = screen
        let x = mainPanel.frame.midX - size.width / 2
        let y = mainPanel.frame.minY - size.height - 8
        cp.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
    }

    private func animateSize(to size: NSSize) {
        guard let panel, let screen = NSScreen.main else { return }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height - 6
        let newFrame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        trackingView?.frame = NSRect(origin: .zero, size: size)
        trackingView?.updateTrackingAreas()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }
}

/// NSView subclass that owns the tracking area for hover detection.
class IslandTrackingView: NSView {
    weak var controller: IslandWindowController?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseDown(with event: NSEvent) {
        if event.buttonNumber == 1 || event.modifierFlags.contains(.control) {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "退出 Jarvis", action: #selector(quit), keyEquivalent: ""))
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    override func mouseEntered(with event: NSEvent) {
        Task { @MainActor in controller?.handleMouseEntered() }
    }

    override func mouseExited(with event: NSEvent) {
        Task { @MainActor in controller?.handleMouseExited() }
    }
}
