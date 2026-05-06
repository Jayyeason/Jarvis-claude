import Foundation

enum GatewayError: Error, LocalizedError {
    case settingsUpdateFailed
    case verifyFailed(String)
    case chatFailed(String)
    case notConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .settingsUpdateFailed:    return "设置更新失败"
        case .verifyFailed(let msg):   return "验证失败: \(msg)"
        case .chatFailed(let msg):     return "请求失败: \(msg)"
        case .notConfigured:           return "请先配置云端 API"
        case .invalidResponse:         return "网关返回无效响应"
        }
    }
}

struct VerifyRequest: Codable {
    let providerId: String
    let apiKey: String
    let baseUrl: String?
    let modelId: String
    let awsAccessKey: String?
    let awsSecretKey: String?
    let region: String?

    enum CodingKeys: String, CodingKey {
        case providerId  = "provider_id"
        case apiKey      = "api_key"
        case baseUrl     = "base_url"
        case modelId     = "model_id"
        case awsAccessKey = "aws_access_key"
        case awsSecretKey = "aws_secret_key"
        case region
    }
}

struct VerifyResponse: Codable {
    let status: String
    let models: [String]?
    let detail: String?
}

struct GatewayConfig: Codable {
    let activeProviderId: String?
    let activeModelId: String?
    let activeModelVision: Bool?
    let providers: [String: ProviderConfig]?

    enum CodingKeys: String, CodingKey {
        case activeProviderId  = "active_provider_id"
        case activeModelId     = "active_model_id"
        case activeModelVision = "active_model_vision"
        case providers
    }
}

actor GatewayClient {
    static let shared = GatewayClient()

    private let baseURL = URL(string: "http://127.0.0.1:8765")!
    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func updateSettings(_ req: SettingsRequest) async throws {
        let url = baseURL.appendingPathComponent("settings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(req)
        request.timeoutInterval = 10
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayError.settingsUpdateFailed
        }
    }

    func verify(_ req: VerifyRequest) async throws -> [String] {
        let url = baseURL.appendingPathComponent("verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(req)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = (try? decoder.decode(VerifyResponse.self, from: data))?.detail ?? "未知错误"
            throw GatewayError.verifyFailed(detail)
        }
        return (try decoder.decode(VerifyResponse.self, from: data)).models ?? []
    }

    func getConfig() async throws -> GatewayConfig {
        let url = baseURL.appendingPathComponent("config")
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(GatewayConfig.self, from: data)
    }

    func chat(_ req: ChatRequest) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(req)
        request.timeoutInterval = 60
        let started = Date()
        jlog("[GatewayClient] POST /chat input_mode=\(req.inputMode) image=\(req.image != nil) message_chars=\(req.message.count)")
        let (data, response) = try await session.data(for: request)
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
        guard let http = response as? HTTPURLResponse else {
            jlog("[GatewayClient] /chat invalid response elapsed=\(elapsed)s bytes=\(data.count)")
            throw GatewayError.invalidResponse
        }
        jlog("[GatewayClient] /chat status=\(http.statusCode) elapsed=\(elapsed)s bytes=\(data.count)")
        guard http.statusCode == 200 else {
            let body = String(data: data.prefix(1000), encoding: .utf8) ?? "<non-utf8>"
            jlog("[GatewayClient] /chat error body=\(body)")
            throw GatewayError.chatFailed("HTTP \(http.statusCode)")
        }
        do {
            return try decoder.decode(ChatResponse.self, from: data)
        } catch {
            let body = String(data: data.prefix(1000), encoding: .utf8) ?? "<non-utf8>"
            jlog("[GatewayClient] /chat decode failed: \(error); body=\(body)")
            throw error
        }
    }

    func health() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let request = URLRequest(url: url, timeoutInterval: 5)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
