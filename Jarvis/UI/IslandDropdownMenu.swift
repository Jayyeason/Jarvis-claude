import AppKit
import SwiftUI

@MainActor
enum IslandDropdownMenu {
    struct Item {
        let title: String
        let action: () -> Void
    }

    private static var panel: NSPanel?
    private static var globalDismissMonitor: Any?

    static func show(items: [Item], buttonOrigin: NSPoint) {
        dismiss()

        let menuView = DropdownMenuView(items: items, onDismiss: { dismiss() })
        let hosting = NSHostingView(rootView: menuView)
        hosting.setFrameSize(hosting.fittingSize)

        let p = UnconstrainedPanel(
            contentRect: NSRect(origin: .zero, size: hosting.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = hosting

        // Left-align with button, appear just below it
        let x = buttonOrigin.x
        let y = buttonOrigin.y - hosting.frame.height - 4
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.orderFrontRegardless()
        panel = p

        // Dismiss on any click outside
        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            Task { @MainActor in dismiss() }
        }
    }

    static func dismiss() {
        panel?.close()
        panel = nil
        if let m = globalDismissMonitor { NSEvent.removeMonitor(m) }
        globalDismissMonitor = nil
    }
}

private struct DropdownMenuView: View {
    let items: [IslandDropdownMenu.Item]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                }
                DropdownMenuItem(title: item.title) {
                    onDismiss()
                    item.action()
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
        )
    }
}

private struct DropdownMenuItem: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.12) : Color.clear)
                        .padding(.horizontal, 4)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
