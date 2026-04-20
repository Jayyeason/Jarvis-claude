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
                    // Black capsule spanning full window height (notch + expanded area)
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: 10
                    )
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
            // Collapsed: fully transparent — notch itself provides the black visual
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

            CapsuleButton(icon: "gearshape", label: nil, action: onSettings)

            divider

            CapsuleButton(icon: "power", label: nil, action: { NSApp.terminate(nil) })
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
