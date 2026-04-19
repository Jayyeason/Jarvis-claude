import Foundation
import Combine

struct ProviderConfig: Codable {
    var modelId: String?
    var baseUrl: String?
    var configured: Bool

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case baseUrl = "base_url"
        case configured
    }
}

let PROVIDER_DISPLAY_NAMES: [String: String] = [
    "openai":       "OpenAI",
    "anthropic":    "Anthropic",
    "google":       "Google Gemini",
    "deepseek":     "DeepSeek",
    "openrouter":   "OpenRouter",
    "moonshot":     "Moonshot",
    "minimax":      "MiniMax",
    "glm":          "GLM（智谱）",
    "zai":          "Z.AI",
    "bedrock":      "Amazon Bedrock",
    "vercel":       "Vercel AI Gateway",
    "synthetic":    "Synthetic",
    "opencode_zen": "OpenCode Zen",
    "ollama":       "Ollama",
    "custom":       "自定义端点",
]

@MainActor
class APIConfigStore: ObservableObject {
    static let shared = APIConfigStore()

    @Published var activeProviderId: String?
    @Published var activeModelId: String?
    @Published var configurations: [String: ProviderConfig] = [:]

    var activeDisplayName: String {
        guard let pid = activeProviderId, let mid = activeModelId else {
            return "未配置 API"
        }
        let name = PROVIDER_DISPLAY_NAMES[pid] ?? pid
        return "\(name) / \(mid)"
    }

    /// Pull current state from Python (no API keys returned).
    func loadFromGateway() async {
        guard let cfg = try? await GatewayClient.shared.getConfig() else { return }
        activeProviderId = cfg.activeProviderId
        activeModelId    = cfg.activeModelId
        configurations   = cfg.providers ?? [:]
    }

    /// Send settings to Python (Python saves to ~/.jarvis/api_config.json).
    func activate(
        providerId: String,
        modelId: String,
        apiKey: String = "",
        baseUrl: String? = nil,
        awsAccessKey: String? = nil,
        awsSecretKey: String? = nil,
        region: String? = nil
    ) async throws {
        let req = SettingsRequest(
            providerId:   providerId,
            modelId:      modelId,
            apiKey:       apiKey,
            baseUrl:      baseUrl,
            awsAccessKey: awsAccessKey,
            awsSecretKey: awsSecretKey,
            region:       region
        )
        try await GatewayClient.shared.updateSettings(req)
        activeProviderId = providerId
        activeModelId    = modelId
        configurations[providerId] = ProviderConfig(
            modelId: modelId, baseUrl: baseUrl, configured: true
        )
    }
}
