import SwiftUI
import AppKit

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
    .init(id: "deepseek",     displayName: "DeepSeek",          section: "主流云端",   fields: [.apiKey],                                    presetModels: ["deepseek-v4-flash", "deepseek-v4-pro"]),
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
            .frame(minWidth: 460)
        }
        .frame(width: 680, height: 520)
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
    @State private var selectedApiKeyId: String = ""
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

    private var providerConfig: ProviderConfig? {
        configStore.configurations[provider.id]
    }

    private var savedApiKeys: [StoredAPIKey] {
        providerConfig?.apiKeys ?? []
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
                        VStack(alignment: .leading, spacing: 8) {
                            if !savedApiKeys.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("已保存 Key")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)

                                    VStack(spacing: 6) {
                                        ForEach(savedApiKeys) { key in
                                            savedApiKeyRow(key)
                                        }
                                    }
                                }
                            }

                            HStack {
                                if showAPIKey {
                                    TextField(savedApiKeys.isEmpty ? "sk-..." : "输入新的 API Key", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField(savedApiKeys.isEmpty ? "sk-..." : "输入新的 API Key", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button { showAPIKey.toggle() } label: {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                            }

                            if !savedApiKeys.isEmpty {
                                Text("输入新 Key 会新增保存；留空则使用当前 Key。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
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

                modelIdSection

                // Actions
                HStack(spacing: 12) {
                    Button("验证") {
                        Task { await saveAndVerify() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying || primaryFieldEmpty)

                    Button("使用此配置") {
                        Task { await activateProvider() }
                    }
                    .disabled(primaryFieldEmpty || isSaving)

                    if isVerifying {
                        ProgressView().scaleEffect(0.8)
                    }
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
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
        .onReceive(configStore.$configurations) { _ in syncSelectedApiKeyIfNeeded() }
    }

    private var primaryFieldEmpty: Bool {
        if provider.fields.contains(.apiKey)
            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedApiKeyId.isEmpty { return true }
        if provider.id == "ollama" && baseUrl.isEmpty { return true }
        if provider.fields.contains(.awsAccessKey) && awsAccessKey.isEmpty { return true }
        if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    private func loadSavedValues() {
        apiKey = ""  // never pre-fill from memory (stored in Python)
        selectedApiKeyId = providerConfig?.activeApiKeyId ?? savedApiKeys.first?.id ?? ""
        baseUrl = providerConfig?.baseUrl ?? ""
        availableModels = []
        selectedModel = providerConfig?.modelId ?? provider.presetModels.first ?? ""
        verifyStatus = isConfigured ? .success : .idle
    }

    private func syncSelectedApiKeyIfNeeded() {
        let ids = Set(savedApiKeys.map(\.id))
        if selectedApiKeyId.isEmpty || !ids.contains(selectedApiKeyId) {
            selectedApiKeyId = providerConfig?.activeApiKeyId ?? savedApiKeys.first?.id ?? ""
        }
    }

    private var modelOptions: [String] {
        unique(provider.presetModels + availableModels)
    }

    private var modelPlaceholder: String {
        provider.presetModels.first ?? "model-id"
    }

    private var modelIdSection: some View {
        fieldSection("模型 ID") {
            HStack(spacing: 8) {
                TextField(modelPlaceholder, text: $selectedModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                if !modelOptions.isEmpty {
                    Menu {
                        ForEach(modelOptions, id: \.self) { model in
                            Button(model) { selectedModel = model }
                        }
                    } label: {
                        Label("模型", systemImage: "list.bullet")
                    }
                    .menuStyle(.button)
                }
            }
        }
    }

    private func saveAndVerify() async {
        isVerifying = true
        verifyStatus = .idle
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)

        let req = VerifyRequest(
            providerId: provider.id,
            apiKey: apiKey,
            apiKeyId: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nonEmpty(selectedApiKeyId) : nil,
            baseUrl: baseUrl.isEmpty ? nil : baseUrl,
            modelId: trimmedModel,
            awsAccessKey: awsAccessKey.isEmpty ? nil : awsAccessKey,
            awsSecretKey: awsSecretKey.isEmpty ? nil : awsSecretKey,
            region: region.isEmpty ? nil : region
        )

        do {
            let models = try await GatewayClient.shared.verify(req)
            availableModels = models
            selectedModel = trimmedModel
            verifyStatus = .success
        } catch {
            verifyStatus = .failure(error.localizedDescription)
        }
        isVerifying = false
    }

    private func activateProvider(apiKeyIdOverride: String? = nil) async {
        isSaving = true
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetApiKeyId = apiKeyIdOverride ?? selectedApiKeyId
        guard !trimmedModel.isEmpty else {
            verifyStatus = .failure("请填写模型 ID")
            isSaving = false
            return
        }
        do {
            try await configStore.activate(
                providerId:   provider.id,
                modelId:      trimmedModel,
                apiKey:       trimmedKey,
                apiKeyId:     trimmedKey.isEmpty ? nonEmpty(targetApiKeyId) : nil,
                baseUrl:      baseUrl.isEmpty ? nil : baseUrl,
                awsAccessKey: awsAccessKey.isEmpty ? nil : awsAccessKey,
                awsSecretKey: awsSecretKey.isEmpty ? nil : awsSecretKey,
                region:       region.isEmpty ? nil : region
            )
            apiKey = ""
            showAPIKey = false
            loadSavedValues()
            verifyStatus = .success
        } catch {
            verifyStatus = .failure(error.localizedDescription)
        }
        isSaving = false
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }

    private func savedApiKeyRow(_ key: StoredAPIKey) -> some View {
        let isActive = key.id == providerConfig?.activeApiKeyId
        return HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "key")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .green : .secondary)
                .frame(width: 16)

            Text(key.maskedKey)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isActive {
                Text("当前")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button("切换") {
                    selectedApiKeyId = key.id
                    Task { await activateProvider(apiKeyIdOverride: key.id) }
                }
                .font(.system(size: 11, weight: .medium))
                .disabled(selectedModel.isEmpty || isSaving)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.green.opacity(0.10) : Color.secondary.opacity(0.08))
        )
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

// ── Local MLX model manager ──────────────────────────────────────────────────

@MainActor
struct ModelManagerPanel: View {
    @State private var managerState: LocalModelsResponse?
    @State private var downloads: [ModelDownloadStatus] = []
    @State private var selectedModelId: String?
    @State private var repoId = ""
    @State private var displayName = ""
    @State private var statusText: String?
    @State private var isRefreshing = false
    @State private var isDownloading = false
    @State private var loadingModelId: String?

    private var installedModels: [LocalModelManifest] {
        managerState?.installed ?? []
    }

    private var selectedModel: LocalModelManifest? {
        installedModels.first { $0.id == selectedModelId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                installedList
                    .frame(minWidth: 260, idealWidth: 300)
                detailPane
                    .frame(minWidth: 430)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .task { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("端侧模型")
                .font(.system(size: 16, weight: .semibold))
            if let statusText {
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                openModelsDir()
            } label: {
                Label("打开目录", systemImage: "folder")
            }
            .disabled(managerState?.modelsDir == nil)

            Button {
                Task { await refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var installedList: some View {
        List(selection: $selectedModelId) {
            Section("已安装") {
                if installedModels.isEmpty {
                    Text("暂无模型")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedModels) { model in
                        HStack(spacing: 8) {
                            Image(systemName: "memorychip")
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(model.repoId)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isActive(model) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(model.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dependencyStatus
                downloadSection
                Divider()
                if let selectedModel {
                    modelDetail(selectedModel)
                } else {
                    Text("选择一个已安装模型")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                downloadStatusList
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dependencyStatus: some View {
        HStack(spacing: 8) {
            dependencyBadge(
                title: "MLX",
                ok: managerState?.mlxAvailable == true,
                missingText: "未安装 mlx-lm"
            )
            dependencyBadge(
                title: "Hugging Face",
                ok: managerState?.huggingfaceHubAvailable == true,
                missingText: "未安装 huggingface_hub"
            )
        }
    }

    private func dependencyBadge(title: String, ok: Bool, missingText: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : .orange)
            Text(ok ? "\(title) 可用" : missingText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("下载模型")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(managerState?.recommended ?? []) { item in
                        Button(item.displayName) {
                            repoId = item.repoId
                            displayName = item.displayName
                        }
                    }
                } label: {
                    Label("推荐", systemImage: "sparkles")
                }
            }

            TextField("Hugging Face ID", text: $repoId)
                .textFieldStyle(.roundedBorder)

            TextField("显示名称（可选）", text: $displayName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button {
                    Task { await startDownload() }
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading || repoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || managerState?.huggingfaceHubAvailable != true)

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                if let path = managerState?.modelsDir {
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadStatusList: some View {
        if !downloads.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("下载状态")
                    .font(.system(size: 13, weight: .semibold))
                ForEach(downloads) { item in
                    HStack(spacing: 8) {
                        Image(systemName: iconForDownloadStatus(item.status))
                            .foregroundColor(colorForDownloadStatus(item.status))
                        Text(item.displayName ?? item.repoId)
                            .lineLimit(1)
                        Spacer()
                        Text(labelForDownloadStatus(item.status))
                            .foregroundColor(.secondary)
                        if let error = item.error, !error.isEmpty {
                            Text(error)
                                .foregroundColor(.red)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private func modelDetail(_ model: LocalModelManifest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.system(size: 16, weight: .semibold))
                    Text(model.repoId)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if isActive(model) {
                    Label("当前使用", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("引擎").foregroundColor(.secondary)
                    Text(model.engine?.uppercased() ?? "MLX")
                }
                GridRow {
                    Text("视觉").foregroundColor(.secondary)
                    Text((model.supportsVision ?? false) ? "支持" : "不支持")
                }
                GridRow {
                    Text("路径").foregroundColor(.secondary)
                    Text(model.localPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 12))

            HStack(spacing: 10) {
                Button {
                    Task { await load(model) }
                } label: {
                    Label("加载", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(managerState?.mlxAvailable != true || loadingModelId != nil)

                Button {
                    Task { await unload() }
                } label: {
                    Label("卸载", systemImage: "stop.circle")
                }
                .disabled(!isActive(model) || loadingModelId != nil)

                Button(role: .destructive) {
                    Task { await confirmDelete(model) }
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(loadingModelId != nil)

                if loadingModelId == model.id {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let next = try await GatewayClient.shared.getLocalModels()
            managerState = next
            downloads = next.downloads
            if let selectedModelId, next.installed.contains(where: { $0.id == selectedModelId }) {
                return
            }
            selectedModelId = next.installed.first(where: { next.activeProviderId == "mlx_local" && $0.id == next.activeModelId })?.id
                ?? next.installed.first?.id
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func startDownload() async {
        let trimmedRepo = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepo.isEmpty else { return }
        isDownloading = true
        statusText = "开始下载 \(trimmedRepo)"
        do {
            let status = try await GatewayClient.shared.downloadModel(
                ModelDownloadRequest(
                    repoId: trimmedRepo,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName,
                    revision: nil
                )
            )
            await pollDownload(modelId: status.modelId)
        } catch {
            statusText = error.localizedDescription
        }
        isDownloading = false
    }

    private func pollDownload(modelId: String) async {
        for _ in 0..<360 {
            do {
                let response = try await GatewayClient.shared.downloadStatus()
                downloads = response.downloads
                if let match = response.downloads.first(where: { $0.modelId == modelId }) {
                    if match.status == "complete" {
                        statusText = "下载完成"
                        await refresh()
                        return
                    }
                    if match.status == "failed" {
                        statusText = match.error ?? "下载失败"
                        return
                    }
                }
            } catch {
                statusText = error.localizedDescription
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        statusText = "下载仍在进行"
    }

    private func load(_ model: LocalModelManifest) async {
        loadingModelId = model.id
        defer { loadingModelId = nil }
        do {
            try await GatewayClient.shared.loadLocalModel(ModelActionRequest(modelId: model.id))
            await APIConfigStore.shared.loadFromGateway()
            statusText = "已加载 \(model.displayName)"
            await refresh()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func unload() async {
        do {
            try await GatewayClient.shared.unloadLocalModel()
            await APIConfigStore.shared.loadFromGateway()
            statusText = "已卸载"
            await refresh()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func confirmDelete(_ model: LocalModelManifest) async {
        let alert = NSAlert()
        alert.messageText = "删除本地模型？"
        alert.informativeText = model.displayName
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        await delete(model)
    }

    private func delete(_ model: LocalModelManifest) async {
        loadingModelId = model.id
        defer { loadingModelId = nil }
        do {
            try await GatewayClient.shared.deleteLocalModel(modelId: model.id)
            await APIConfigStore.shared.loadFromGateway()
            statusText = "已删除 \(model.displayName)"
            await refresh()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func openModelsDir() {
        guard let path = managerState?.modelsDir else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func isActive(_ model: LocalModelManifest) -> Bool {
        managerState?.activeProviderId == "mlx_local" && managerState?.activeModelId == model.id
    }

    private func labelForDownloadStatus(_ status: String) -> String {
        switch status {
        case "queued": return "排队中"
        case "downloading": return "下载中"
        case "complete": return "完成"
        case "failed": return "失败"
        default: return status
        }
    }

    private func iconForDownloadStatus(_ status: String) -> String {
        switch status {
        case "queued": return "clock"
        case "downloading": return "arrow.down.circle"
        case "complete": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private func colorForDownloadStatus(_ status: String) -> Color {
        switch status {
        case "complete": return .green
        case "failed": return .red
        case "downloading": return .blue
        default: return .secondary
        }
    }
}
