import SwiftUI

/// The SwiftUI content rendered inside the island capsule window.
struct IslandCapsuleView: View {
    let isExpanded: Bool
    let isCapturing: Bool
    let onCapture: () -> Void
    let onSettings: () -> Void

    @ObservedObject private var configStore = APIConfigStore.shared

    var body: some View {
        ZStack {
            // Black capsule background
            Capsule()
                .fill(Color.black)

            if isCapturing {
                capturingContent
            } else if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - States

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
            Text("Jarvis")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
    }

    private var expandedContent: some View {
        HStack(spacing: 0) {
            // Capture button
            CapsuleButton(icon: "camera.viewfinder", label: "截图", action: onCapture)

            divider

            // Model name
            Text(configStore.activeDisplayName)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 120)
                .padding(.horizontal, 8)

            divider

            // Settings button
            CapsuleButton(icon: "gearshape", label: nil, action: onSettings)
        }
        .padding(.horizontal, 8)
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
