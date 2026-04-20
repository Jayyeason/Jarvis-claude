import SwiftUI

struct IslandPanel: View {
    @ObservedObject var configStore = APIConfigStore.shared
    let onCaptureRequested: () -> Void
    let onSettingsRequested: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Logo
            JarvisLogoView()
                .padding(.leading, 6)

            // Screenshot button
            IslandButton(icon: "camera.viewfinder", label: "截图") {
                onCaptureRequested()
            }

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            // Current model indicator
            Text(configStore.activeDisplayName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 140)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            // Settings button
            IslandButton(icon: "gearshape", label: nil) {
                onSettingsRequested()
            }
            .padding(.trailing, 6)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}

private struct IslandButton: View {
    let icon: String
    let label: String?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

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
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .opacity(isPressed ? 0.7 : 1.0)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct JarvisLogoView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor)
                .frame(width: 16, height: 16)
            Text("J")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
