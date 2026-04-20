import AppKit
import SwiftUI

@MainActor
class IslandWindowController {
    static let shared = IslandWindowController()

    private var panel: NSPanel?
    private var confirmationPanel: NSPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private(set) var isExpanded = false
    private(set) var isCapturing = false

    var onCaptureRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?

    // MARK: - Notch geometry

    var notchRect: NSRect {
        guard let screen = NSScreen.main,
              let tl = screen.auxiliaryTopLeftArea,
              let tr = screen.auxiliaryTopRightArea else {
            let s = NSScreen.main!
            let mh = NSStatusBar.system.thickness
            let w: CGFloat = 180
            return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - mh, width: w, height: mh)
        }
        return NSRect(x: tl.maxX, y: tl.minY, width: tr.minX - tl.maxX, height: tl.height)
    }

    private var expandedSize: NSSize {
        NSSize(width: max(notchRect.width, 240), height: notchRect.height + 44)
    }

    // MARK: - Setup

    func setup() {
        let nr = notchRect
        jlog("[Island] notchRect=\(nr)")

        let p = makePanel()
        self.panel = p
        setContentFrame(size: nr.size, animated: false)
        updateContent()
        p.orderFrontRegardless()

        startMouseTracking()
        jlog("[Island] setup complete, mouse tracking started")
    }

    // MARK: - State transitions

    func showCapturing() {
        isCapturing = true
        updateContent()
        if !isExpanded { expandPanel() }
    }

    func showSuccess() {
        isCapturing = false
        updateContent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.restoreIdle()
        }
    }

    func restoreIdle() {
        isCapturing = false
        if isExpanded { collapsePanel() } else { updateContent() }
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

        let cp = makePanel()
        cp.hasShadow = true
        cp.contentViewController = vc
        confirmationPanel = cp

        if let mainFrame = panel?.frame {
            let x = mainFrame.midX - cardSize.width / 2
            let y = mainFrame.minY - cardSize.height - 8
            cp.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: cardSize), display: false)
        }
        cp.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private

    private func checkHoverState() {
        let loc = NSEvent.mouseLocation
        let inNotch = notchRect.contains(loc)
        let inContent = panel?.frame.contains(loc) ?? false

        if (inNotch || inContent) && !isExpanded {
            jlog("[Island] hover enter → expand")
            expandPanel()
        } else if !inNotch && !inContent && isExpanded && !isCapturing {
            jlog("[Island] hover exit → collapse")
            collapsePanel()
        }
    }

    private func startMouseTracking() {
        // Global monitor fires when mouse is over other apps / desktop
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { self?.checkHoverState() }
        }
        // Local monitor fires when mouse is over our own panel
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.checkHoverState()
            return event
        }
    }

    private func expandPanel() {
        isExpanded = true
        updateContent()
        setContentFrame(size: expandedSize, animated: true)
    }

    private func collapsePanel() {
        isExpanded = false
        updateContent()
        setContentFrame(size: notchRect.size, animated: true)
    }

    private func updateContent() {
        guard let panel else { return }
        let nr = notchRect
        let view = IslandCapsuleView(
            isExpanded: isExpanded,
            isCapturing: isCapturing,
            notchHeight: nr.height,
            onCapture: { [weak self] in self?.onCaptureRequested?() },
            onSettings: { [weak self] in self?.onSettingsRequested?() }
        )
        // Reuse existing hosting view to avoid flash during animation
        if let hosting = panel.contentView?.subviews.first as? NSHostingView<IslandCapsuleView> {
            hosting.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = panel.contentView?.bounds ?? .zero
            hosting.autoresizingMask = [.width, .height]
            panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
            panel.contentView?.addSubview(hosting)
        }
    }

    /// Top edge of window = notch top (maxY), window grows downward.
    private func setContentFrame(size: NSSize, animated: Bool) {
        guard let panel else { return }
        let nr = notchRect
        let x = nr.midX - size.width / 2
        let y = nr.maxY - size.height
        let newFrame = NSRect(origin: NSPoint(x: x, y: y), size: size)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func makePanel() -> NSPanel {
        let p = UnconstrainedPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        return p
    }
}

// MARK: - Panel subclass

/// Bypasses macOS constraint that keeps windows below the menu bar.
class UnconstrainedPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出 Jarvis", action: #selector(NSApp.terminate(_:)), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? NSView())
    }
}
