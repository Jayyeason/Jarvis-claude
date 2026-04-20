import AppKit
import SwiftUI

@MainActor
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var confirmationPopover: NSPopover?

    override init() {
        super.init()
        setupStatusItem()
        setupCapture()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        guard let button = statusItem.button else { return }

        let logo = NSHostingView(rootView: JarvisLogoView())
        logo.frame = NSRect(x: 5, y: 0, width: 22, height: NSStatusBar.system.thickness)
        button.addSubview(logo)

        button.action = #selector(handleButtonClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupCapture() {
        CaptureManager.shared.onCaptureStart = { [weak self] in
            Task { @MainActor in self?.showCapturing() }
        }
        CaptureManager.shared.onCaptureComplete = { [weak self] response in
            Task { @MainActor in self?.handleCaptureResult(response) }
        }
        CaptureManager.shared.onCaptureError = { [weak self] error in
            Task { @MainActor in self?.restoreButton() }
        }
    }

    @objc private func handleButtonClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "退出 Jarvis", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.popUpMenu(menu)
            return
        }
        if let p = popover, p.isShown {
            p.close()
            popover = nil
            return
        }
        guard let button = statusItem.button else { return }

        let p = NSPopover()
        p.contentViewController = NSHostingController(rootView: IslandPanel(
            onCaptureRequested: { [weak self] in
                Task { @MainActor in
                    self?.closePopover()
                    self?.triggerCapture()
                }
            },
            onSettingsRequested: { [weak self] in
                Task { @MainActor in
                    self?.closePopover()
                    self?.openSettings()
                }
            }
        ))
        p.behavior = .transient
        p.animates = true
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p
    }

    private func closePopover() {
        popover?.close()
        popover = nil
    }

    func triggerCapture() {
        CaptureManager.shared.capture()
    }

    func openSettings() {
        APISettingsWindowManager.shared.open()
    }

    private func showCapturing() {
        guard let button = statusItem.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
        let view = NSHostingView(rootView: CapturingIndicator())
        view.frame = NSRect(x: 0, y: 0, width: 80, height: NSStatusBar.system.thickness)
        button.addSubview(view)
        statusItem.length = 80
    }

    private func handleCaptureResult(_ response: ChatResponse) {
        let result = RecognitionResult.from(response)
        restoreButton()
        showConfirmationCard(result: result)
    }

    private func restoreButton() {
        guard let button = statusItem.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
        let logo = NSHostingView(rootView: JarvisLogoView())
        logo.frame = NSRect(x: 5, y: 0, width: 22, height: NSStatusBar.system.thickness)
        button.addSubview(logo)
        statusItem.length = 32
    }

    func showSuccess() {
        guard let button = statusItem.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
        let view = NSHostingView(rootView: SuccessIndicator())
        view.frame = NSRect(x: 0, y: 0, width: 50, height: NSStatusBar.system.thickness)
        button.addSubview(view)
        statusItem.length = 50

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.restoreButton()
        }
    }

    private func showConfirmationCard(result: RecognitionResult) {
        guard result.eventType != nil else { return }

        confirmationPopover?.close()

        let vc = NSHostingController(rootView: ConfirmationCard(
            result: result,
            onDismiss: { [weak self] in
                Task { @MainActor in
                    self?.confirmationPopover?.close()
                    self?.confirmationPopover = nil
                }
            },
            onSuccess: { [weak self] in
                Task { @MainActor in
                    self?.confirmationPopover?.close()
                    self?.confirmationPopover = nil
                    self?.showSuccess()
                }
            }
        ))

        // Pre-calculate size synchronously so popover shows at full size immediately
        vc.view.setFrameSize(NSSize(width: 300, height: 600))
        vc.view.layoutSubtreeIfNeeded()
        let h = vc.view.fittingSize.height
        vc.preferredContentSize = NSSize(width: 300, height: h > 50 ? h : 280)

        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .semitransient
        p.animates = false  // no animation avoids the size-jump flash

        guard let button = statusItem.button else { return }
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        confirmationPopover = p
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
