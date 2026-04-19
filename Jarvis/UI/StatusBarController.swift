import AppKit
import SwiftUI

@MainActor
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isExpanded = false

    // Panels shown below the island
    private var confirmationWindow: NSWindow?
    private var isCapturing = false
    private var pendingResult: ChatResponse?

    override init() {
        super.init()
        setupStatusItem()
        setupCapture()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        updateButtonToSilent(button)

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        button.action = #selector(handleButtonClick)
        button.target = self
    }

    private func setupCapture() {
        CaptureManager.shared.onCaptureStart = { [weak self] in
            Task { @MainActor in
                self?.showCapturing()
            }
        }
        CaptureManager.shared.onCaptureComplete = { [weak self] response in
            Task { @MainActor in
                self?.handleCaptureResult(response)
            }
        }
        CaptureManager.shared.onCaptureError = { [weak self] error in
            Task { @MainActor in
                self?.showError(error)
            }
        }
    }

    private func updateButtonToSilent(_ button: NSButton) {
        let logo = NSHostingView(rootView: JarvisLogoView())
        logo.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(logo)
        button.frame = NSRect(x: 0, y: 0, width: 32, height: NSStatusBar.system.thickness)
        statusItem.length = 32
    }

    private func updateButtonToExpanded(_ button: NSButton) {
        let panel = NSHostingView(rootView: IslandPanel(
            onDismiss: {},
            onCaptureRequested: { [weak self] in
                Task { @MainActor in self?.triggerCapture() }
            },
            onSettingsRequested: { [weak self] in
                Task { @MainActor in self?.openSettings() }
            }
        ))
        panel.frame = NSRect(x: 0, y: 0, width: 380, height: NSStatusBar.system.thickness)
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(panel)
        statusItem.length = 380
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isExpanded else { return }
        isExpanded = true
        if let button = statusItem.button {
            withAnimation(.easeOut(duration: 0.2)) {
                updateButtonToExpanded(button)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard isExpanded else { return }
        isExpanded = false
        if let button = statusItem.button {
            withAnimation(.easeOut(duration: 0.2)) {
                updateButtonToSilent(button)
            }
        }
    }

    @objc private func handleButtonClick() {
        // Clicks are handled inside the SwiftUI panel buttons
    }

    func triggerCapture() {
        CaptureManager.shared.capture()
    }

    func openSettings() {
        APISettingsWindowManager.shared.open()
    }

    private func showCapturing() {
        guard let button = statusItem.button else { return }
        let view = NSHostingView(rootView: CapturingIndicator())
        view.frame = NSRect(x: 0, y: 0, width: 80, height: NSStatusBar.system.thickness)
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(view)
        statusItem.length = 80
        isExpanded = false
    }

    private func handleCaptureResult(_ response: ChatResponse) {
        let result = RecognitionResult.from(response)
        showConfirmationCard(result: result)
        restoreButton()
    }

    private func showError(_ message: String) {
        restoreButton()
        // Show brief error in island
    }

    private func restoreButton() {
        guard let button = statusItem.button else { return }
        updateButtonToSilent(button)
        isExpanded = false
    }

    func showSuccess() {
        guard let button = statusItem.button else { return }
        let view = NSHostingView(rootView: SuccessIndicator())
        view.frame = NSRect(x: 0, y: 0, width: 50, height: NSStatusBar.system.thickness)
        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(view)
        statusItem.length = 50
        isExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.restoreButton()
        }
    }

    private func showConfirmationCard(result: RecognitionResult) {
        guard result.eventType != nil else { return }

        confirmationWindow?.close()

        let hostingView = NSHostingView(rootView: ConfirmationCard(
            result: result,
            onDismiss: { [weak self] in
                Task { @MainActor in
                    self?.confirmationWindow?.close()
                    self?.confirmationWindow = nil
                }
            },
            onSuccess: { [weak self] in
                Task { @MainActor in
                    self?.confirmationWindow?.close()
                    self?.confirmationWindow = nil
                    self?.showSuccess()
                }
            }
        ))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .statusBar

        // Position below the status item button
        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonFrame = buttonWindow.convertToScreen(button.frame)
            let windowOrigin = NSPoint(
                x: buttonFrame.midX - 150,
                y: buttonFrame.minY - hostingView.fittingSize.height - 4
            )
            window.setFrameOrigin(windowOrigin)
        }

        hostingView.setFrameSize(hostingView.fittingSize)
        var frame = window.frame
        frame.size = hostingView.fittingSize
        window.setFrame(frame, display: true)

        window.orderFront(nil)
        confirmationWindow = window
    }
}

private struct CapturingIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.6)
            Text("识别中")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }
}

private struct SuccessIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.green)
            Text("已写入")
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
    }
}
