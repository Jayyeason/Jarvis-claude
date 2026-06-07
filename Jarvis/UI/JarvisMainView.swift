import SwiftUI

struct JarvisMainView: View {
    @ObservedObject private var configStore = APIConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jarvis")
                        .font(.system(size: 20, weight: .semibold))
                    Text(configStore.activeDisplayName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    CaptureManager.shared.capture()
                } label: {
                    Label("截图识别", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    APISettingsWindowManager.shared.open()
                } label: {
                    Label("配置 API", systemImage: "key")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    ModelManagerWindowManager.shared.open()
                } label: {
                    Label("端侧模型", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)

            HStack {
                Label("快捷键", systemImage: "keyboard")
                    .foregroundColor(.secondary)
                Spacer()
                Text("⌘⇧J")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(22)
        .frame(width: 460)
        .task {
            await configStore.loadFromGateway()
        }
    }
}
