import SwiftUI

// ── Provider metadata ─────────────────────────────────────────────────────────

struct ProviderInfo: Identifiable {
    let id: String
    let displayName: String
    let section: String
    let fields: [FieldType]
    let presetModels: [String]

    enum FieldType { case apiKey, baseUrl, awsAccessKey, awsSecretKey, region }
}

private let allProviders: [ProviderInfo] = [
    .init(id: "openai",       displayName: "OpenAI",           section: "主流云端",   fields: [.apiKey],                                    presetModels: ["gpt-4o", "gpt-4o-mini"]),
    .init(id: "anthropic",    displayName: "Anthropic",         section: "主流云端",   fields: [.apiKey],                                    presetModels: ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-6"]),
    .init(id: "google",       displayName: "Google Gemini",     section: "主流云端",   fields: [.apiKey],                                    presetModels: ["gemini-2.0-flash", "gemini-1.5-pro"]),
    .init(id: "deepseek",     displayName: "DeepSeek",          section: "主流云端",   fields: [.apiKey],                                    presetModels: ["deepseek-chat", "deepseek-reasoner"]),
    .init(id: "openrouter",   displayName: "OpenRouter",        section: "主流云端",   fields: [.apiKey],                                    presetModels: []),
    .init(id: "moonshot",     displayName: "Moonshot（月之暗面）", section: "国内云端", fields: [.apiKey],                                    presetModels: ["moonshot-v1-8k", "moonshot-v1-32k"]),
    .init(id: "minimax",      displayName: "MiniMax",           section: "国内云端",   fields: [.apiKey],                                    presetModels: ["MiniMax-Text-01"]),
    .init(id: "glm",          displayName: "GLM（智谱）",        section: "国内云端",   fields: [.apiKey],                                    presetModels: ["glm-4-plus", "glm-4v-plus"]),
    .init(id: "zai",          displayName: "Z.AI",              section: "国内云端",   fields: [.apiKey],                                    presetModels: ["glm-4-plus"]),
    .init(id: "bedrock",      displayName: "Amazon Bedrock",    section: "企业/开发者", fields: [.awsAccessKey, .awsSecretKey, .region],       presetModels: ["anthropic.claude-sonnet-4-5-20251001-v2:0"]),
    .init(id: "vercel",       displayName: "Vercel AI Gateway", section: "企业/开发者", fields: [.apiKey, .baseUrl],                          presetModels: []),
    .init(id: "synthetic",    displayName: "Synthetic",         section: "企业/开发者", fields: [.apiKey],                                    presetModels: []),
    .init(id: "opencode_zen", displayName: "OpenCode Zen",      section: "企业/开发者", fields: [.apiKey],                                    presetModels: []),
    .init(id: "ollama",       displayName: "Ollama（本地服务）", section: "本地服务",   fields: [.baseUrl],                                   presetModels: []),
    .init(id: "custom",       displayName: "自定义端点",         section: "自定义",     fields: [.baseUrl, .apiKey],                           presetModels: []),
]

private let sections = ["主流云端", "国内云端", "企业/开发者", "本地服务", "自定义"]

// ── Main panel ────────────────────────────────────────────────────────────────

struct APISettingsPanel: View {
    @ObservedObject var configStore = APIConfigStore.shared
    @State private var selectedProviderId: String = allProviders[0].id

    private var selectedProvider: ProviderInfo {
        allProviders.first { $0.id == selectedProviderId } ?? allProviders[0]
    }

    var body: some View {
        HSplitView {
            providerList
                .frame(minWidth: 160, maxWidth: 180)

            ProviderConfigForm(
                provider: selectedProvider,
                isConfigured: configStore.configurations[selectedProviderId]?.configured ?? false
            )
            .frame(minWidth: 420)
        }
        .frame(width: 620, height: 460)
    }

    private var providerList: some View {
        List(selection: $selectedProviderId) {
            ForEach(sections, id: \.self) { section in
                let items = allProviders.filter { $0.section == section }
                if !items.isEmpty {
                    Section(header: Text(section).font(.system(size: 11)).foregroundColor(.secondary)) {
                        ForEach(items) { p in
                            HStack(spacing: 6) {
                                if configStore.configurations[p.id]?.configured == true {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 11))
                                }
                                Text(p.displayName)
                                    .font(.system(size: 13))
                            }
                            .tag(p.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// ── Per-provider config form ──────────────────────────────────────────────────

private struct ProviderConfigForm: View {
    let provider: ProviderInfo
    let isConfigured: Bool

    @ObservedObject var configStore = APIConfigStore.shared

    @State private var apiKey: String = ""
    @State private var baseUrl: String = ""
    @State private var awsAccessKey: String = ""
    @State private var awsSecretKey: String = ""
    @State private var region: String = "us-east-1"
    @State private var availableModels: [String] = []
    @State private var selectedModel: String = ""
    @State private var isVerifying = false
    @State private var isSaving = false
    @State private var verifyStatus: VerifyStatus = .idle
    @State private var showAPIKey = false

    enum VerifyStatus {
        case idle, success, failure(String)
        var label: String {
            switch self {
            case .idle: return ""
            case .success: return "✅ 已连接"
            case .failure(let msg): return "❌ \(msg)"
            }
        }
        var color: Color {
            switch self {
            case .success: return .green
            case .failure: return .red
            default: return .clear
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title + status
                HStack {
                    Text(provider.displayName)
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    if case .success = verifyStatus {
                        Text(verifyStatus.label)
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    } else if case .failure = verifyStatus {
                        Text(verifyStatus.label)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }

                // Fields
                if provider.fields.contains(.apiKey) {
                    fieldSection("API Key") {
                        HStack {
                            if showAPIKey {
                                TextField("sk-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button { showAPIKey.toggle() } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if provider.fields.contains(.baseUrl) {
                    fieldSection(provider.id == "ollama" ? "服务地址" : "Base URL") {
                        TextField("http://localhost:11434", text: $baseUrl)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if provider.fields.contains(.awsAccessKey) {
                    fieldSection("AWS Access Key ID") {
                        SecureField("AKIA...", text: $awsAccessKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    fieldSection("AWS Secret Access Key") {
                        SecureField("••••••••", text: $awsSecretKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    fieldSection("Region") {
                        TextField("us-east-1", text: $region)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Actions
                HStack(spacing: 12) {
                    Button("保存并验证") {
                        Task { await saveAndVerify() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying || primaryFieldEmpty)

                    if isVerifying {
                        ProgressView().scaleEffect(0.8)
                    }
                }

                // Model selection (after verify)
                if !availableModels.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("可用模型")
                            .font(.system(size: 13, weight: .semibold))

                        Picker("选择模型", selection: $selectedModel) {
                            ForEach(availableModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 300)

                        Button("使用此配置") {
                            Task { await activateProvider() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedModel.isEmpty || isSaving)
                    }
                }

                if configStore.activeProviderId == provider.id {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("当前激活")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .onAppear { loadSavedValues() }
        .onChange(of: provider.id) { _ in loadSavedValues() }
    }

    private var primaryFieldEmpty: Bool {
        if provider.fields.contains(.apiKey) && apiKey.isEmpty { return true }
        if provider.id == "ollama" && baseUrl.isEmpty { return true }
        if provider.fields.contains(.awsAccessKey) && awsAccessKey.isEmpty { return true }
        return false
    }

    private func loadSavedValues() {
        apiKey = ""  // never pre-fill from memory (stored in Python)
        baseUrl = configStore.configurations[provider.id]?.baseUrl ?? ""
        availableModels = []
        selectedModel = configStore.configurations[provider.id]?.modelId ?? provider.presetModels.first ?? ""
        verifyStatus = isConfigured ? .success : .idle
    }

    private func saveAndVerify() async {
        isVerifying = true
        verifyStatus = .idle

        let req = VerifyRequest(
            providerId: provider.id,
            apiKey: apiKey,
            baseUrl: baseUrl.isEmpty ? nil : baseUrl,
            modelId: provider.presetModels.first ?? "",
            awsAccessKey: awsAccessKey.isEmpty ? nil : awsAccessKey,
            awsSecretKey: awsSecretKey.isEmpty ? nil : awsSecretKey,
            region: region.isEmpty ? nil : region
        )

        do {
            let models = try await GatewayClient.shared.verify(req)
            availableModels = models.isEmpty ? provider.presetModels : models
            selectedModel = availableModels.first ?? ""
            verifyStatus = .success
        } catch {
            verifyStatus = .failure(error.localizedDescription)
        }
        isVerifying = false
    }

    private func activateProvider() async {
        isSaving = true
        do {
            try await configStore.activate(
                providerId:   provider.id,
                modelId:      selectedModel,
                apiKey:       apiKey,
                baseUrl:      baseUrl.isEmpty ? nil : baseUrl,
                awsAccessKey: awsAccessKey.isEmpty ? nil : awsAccessKey,
                awsSecretKey: awsSecretKey.isEmpty ? nil : awsSecretKey,
                region:       region.isEmpty ? nil : region
            )
        } catch {
            verifyStatus = .failure(error.localizedDescription)
        }
        isSaving = false
    }

    @ViewBuilder
    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            content()
        }
    }
}
