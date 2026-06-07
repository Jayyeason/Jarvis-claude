import AppKit
import SwiftUI

@MainActor
enum IslandDropdownMenu {
    struct Item {
        let title: String
        let subtitle: String?
        let systemImage: String?
        let isSelected: Bool
        let action: () -> Void

        init(
            title: String,
            subtitle: String? = nil,
            systemImage: String? = nil,
            isSelected: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.systemImage = systemImage
            self.isSelected = isSelected
            self.action = action
        }
    }

    private static var panel: NSPanel?
    private static var globalDismissMonitor: Any?

    static func show(items: [Item], buttonOrigin: NSPoint, width: CGFloat = 120) {
        dismiss()

        let menuView = DropdownMenuView(items: items, width: width, onDismiss: { dismiss() })
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
    let width: CGFloat
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
                DropdownMenuItem(item: item) {
                    onDismiss()
                    item.action()
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
        )
    }
}

private struct DropdownMenuItem: View {
    let item: IslandDropdownMenu.Item
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.72))
                        .frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.52))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .frame(width: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, item.subtitle == nil ? 7 : 9)
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
