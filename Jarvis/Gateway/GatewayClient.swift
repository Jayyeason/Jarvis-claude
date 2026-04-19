import Foundation

enum GatewayError: Error, LocalizedError {
    case settingsUpdateFailed
    case verifyFailed(String)
    case chatFailed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .settingsUpdateFailed: return "设置更新失败"
        case .verifyFailed(let msg): return "验证失败: \(msg)"
        case .chatFailed(let msg): return "请求失败: \(msg)"
        case .notConfigured: return "请先配置云端 API"
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
        case providerId = "provider_id"
        case apiKey = "api_key"
        case baseUrl = "base_url"
        case modelId = "model_id"
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
        let vr = try decoder.decode(VerifyResponse.self, from: data)
        return vr.models ?? []
    }

    func chat(_ req: ChatRequest) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(req)
        request.timeoutInterval = 60

        let (data, _) = try await session.data(for: request)
        return try decoder.decode(ChatResponse.self, from: data)
    }

    func health() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let request = URLRequest(url: url, timeoutInterval: 5)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
