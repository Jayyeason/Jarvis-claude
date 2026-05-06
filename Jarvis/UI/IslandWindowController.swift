import AppKit
import SwiftUI

@MainActor
class IslandWindowController {
    static let shared = IslandWindowController()

    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private(set) var isExpanded = false
    private(set) var isCapturing = false
    private(set) var isSuccess = false
    private(set) var pendingResult: RecognitionResult?

    var onCaptureRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onTaskListRequested: (() -> Void)?

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
        NSSize(width: max(notchRect.width, 280), height: notchRect.height + 44)
    }

    private var confirmationSize: NSSize {
        NSSize(width: max(notchRect.width, 340), height: notchRect.height + 280)
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
        jlog("[Island] setup complete")
    }

    // MARK: - State transitions

    func showCapturing() {
        jlog("[Island] showCapturing")
        isCapturing = true
        pendingResult = nil
        updateContent()
        if !isExpanded { expandPanel() }
    }

    func showConfirmation(result: RecognitionResult) {
        jlog("[Island] showConfirmation type=\(result.eventType?.rawValue ?? "none")")
        isCapturing = false
        pendingResult = result
        updateContent()
        if !isExpanded { expandPanel(size: confirmationSize) }
        else { setContentFrame(size: confirmationSize, animated: true) }
    }

    func showSuccess() {
        isCapturing = false
        pendingResult = nil
        isSuccess = true
        updateContent()
        setContentFrame(size: expandedSize, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.isSuccess = false
            self?.restoreIdle()
        }
    }

    func restoreIdle() {
        jlog("[Island] restoreIdle")
        isCapturing = false
        pendingResult = nil
        if isExpanded { collapsePanel() } else { updateContent() }
    }

    // MARK: - Private

    private func checkHoverState() {
        guard pendingResult == nil && !isCapturing else { return }
        let loc = NSEvent.mouseLocation
        let inNotch = notchRect.contains(loc)
        let inContent = panel?.frame.contains(loc) ?? false

        if (inNotch || inContent) && !isExpanded {
            jlog("[Island] hover enter → expand")
            expandPanel()
        } else if !inNotch && !inContent && isExpanded {
            jlog("[Island] hover exit → collapse")
            collapsePanel()
        }
    }

    private func startMouseTracking() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { self?.checkHoverState() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.checkHoverState()
            return event
        }
    }

    private func expandPanel(size: NSSize? = nil) {
        isExpanded = true
        updateContent()
        setContentFrame(size: size ?? expandedSize, animated: true)
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
            isSuccess: isSuccess,
            pendingResult: pendingResult,
            notchHeight: nr.height,
            onCapture: { [weak self] in self?.onCaptureRequested?() },
            onTaskList: { [weak self] in self?.onTaskListRequested?() },
            onSettings: { [weak self] in self?.onSettingsRequested?() },
            onConfirmSuccess: { [weak self] in self?.showSuccess() },
            onConfirmDismiss: { [weak self] in self?.restoreIdle() }
        )
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

    private func setContentFrame(size: NSSize, animated: Bool) {
        guard let panel else { return }
        let nr = notchRect
        let x = nr.midX - size.width / 2
        let y = nr.maxY - size.height
        let newFrame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                ctx.allowsImplicitAnimation = true
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
