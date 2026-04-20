import SwiftUI

/// The SwiftUI content rendered inside the island capsule window.
struct IslandCapsuleView: View {
    let isExpanded: Bool
    let isCapturing: Bool
    let notchHeight: CGFloat
    let onCapture: () -> Void
    let onSettings: () -> Void

    @ObservedObject private var configStore = APIConfigStore.shared

    var body: some View {
        GeometryReader { geo in
            if isExpanded || isCapturing {
                ZStack(alignment: .top) {
                    // Notch-shaped black background
                    NotchShape(topRadius: 10, bottomRadius: 20)
                        .fill(Color.black)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // Content sits below the notch area
                    VStack(spacing: 0) {
                        Color.clear.frame(height: notchHeight)
                        Group {
                            if isCapturing {
                                capturingContent
                            } else {
                                expandedContent
                            }
                        }
                        .frame(height: geo.size.height - notchHeight)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var expandedContent: some View {
        HStack(spacing: 0) {
            CapsuleButton(icon: "camera.viewfinder", label: nil, action: onCapture)

            divider

            ProviderIcon(providerId: configStore.activeProviderId)
                .padding(.horizontal, 10)

            divider

            SettingsMenuButton(onSettings: onSettings)
        }
        .padding(.horizontal, 4)
    }

    private var capturingContent: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.55)
                .tint(.white)
            Text("识别中…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 18)
    }
}

private struct CapsuleButton: View {
    let icon: String
    let label: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                if let label {
                    Text(label)
                        .font(.system(size: 12))
                }
            }
            .foregroundColor(isHovered ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SettingsMenuButton: View {
    let onSettings: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 12))
            .foregroundColor(isHovered ? .white : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.clear)
            )
            .onHover { isHovered = $0 }
            .onTapGesture { showNSMenu() }
    }

    private func showNSMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "模型设置", action: nil, keyEquivalent: "")
        settingsItem.representedObject = onSettings as AnyObject
        settingsItem.target = MenuActionProxy.shared
        settingsItem.action = #selector(MenuActionProxy.handleSettings(_:))
        MenuActionProxy.shared.onSettings = onSettings
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Pop up at current mouse location
        let loc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: loc.x, y: loc.y), in: nil)
    }
}

@MainActor
private class MenuActionProxy: NSObject {
    static let shared = MenuActionProxy()
    var onSettings: (() -> Void)?

    @objc func handleSettings(_ sender: Any?) {
        onSettings?()
    }
}

private struct ProviderIcon: View {
    let providerId: String?

    var body: some View {
        let assetName = "provider_\(providerId ?? "")"
        if let img = NSImage(named: assetName) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: "cpu")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 8

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tr = topRadius
        let br = min(bottomRadius, w / 2, h / 2)

        path.move(to: CGPoint(x: -tr, y: 0))
        path.addLine(to: CGPoint(x: w + tr, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: tr), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: br, y: h))
        path.addArc(center: CGPoint(x: br, y: h - br), radius: br,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tr))
        path.addQuadCurve(to: CGPoint(x: -tr, y: 0), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}
