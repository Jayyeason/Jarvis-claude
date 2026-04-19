import Foundation
import Combine

struct APIConfig: Codable {
    var activeProviderId: String?
    var activeModelId: String?
    var providers: [String: ProviderConfig]
}

struct ProviderConfig: Codable {
    var modelId: String
    var baseUrl: String?
    var configured: Bool
}

let PROVIDER_DISPLAY_NAMES: [String: String] = [
    "openai": "OpenAI",
    "anthropic": "Anthropic",
    "google": "Google Gemini",
    "deepseek": "DeepSeek",
    "openrouter": "OpenRouter",
    "moonshot": "Moonshot",
    "minimax": "MiniMax",
    "glm": "GLM（智谱）",
    "zai": "Z.AI",
    "bedrock": "Amazon Bedrock",
    "vercel": "Vercel AI Gateway",
    "synthetic": "Synthetic",
    "opencode_zen": "OpenCode Zen",
    "ollama": "Ollama",
    "custom": "自定义端点"
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

    private let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".jarvis")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("api_config.json")
    }()

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        return e
    }()

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? decoder.decode(APIConfig.self, from: data) else { return }
        activeProviderId = config.activeProviderId
        activeModelId = config.activeModelId
        configurations = config.providers
    }

    func save() {
        let config = APIConfig(
            activeProviderId: activeProviderId,
            activeModelId: activeModelId,
            providers: configurations
        )
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    func saveAPIKey(_ key: String, for providerId: String) {
        KeychainHelper.save(key, for: "jarvis.api_key.\(providerId)")
    }

    func loadAPIKey(for providerId: String) -> String? {
        KeychainHelper.load("jarvis.api_key.\(providerId)")
    }

    func deleteAPIKey(for providerId: String) {
        KeychainHelper.delete("jarvis.api_key.\(providerId)")
    }

    func activate(providerId: String, modelId: String, baseUrl: String? = nil) async throws {
        activeProviderId = providerId
        activeModelId = modelId
        if configurations[providerId] == nil {
            configurations[providerId] = ProviderConfig(modelId: modelId, configured: true)
        } else {
            configurations[providerId]?.modelId = modelId
            configurations[providerId]?.configured = true
        }
        save()

        let apiKey = loadAPIKey(for: providerId) ?? ""
        let req = SettingsRequest(
            providerId: providerId,
            modelId: modelId,
            apiKey: apiKey,
            baseUrl: baseUrl ?? configurations[providerId]?.baseUrl,
            awsAccessKey: nil,
            awsSecretKey: nil,
            region: nil
        )
        try await GatewayClient.shared.updateSettings(req)
    }
}
