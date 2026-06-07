import Foundation

enum GatewayError: Error, LocalizedError {
    case settingsUpdateFailed
    case verifyFailed(String)
    case chatFailed(String)
    case modelActionFailed(String)
    case notConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .settingsUpdateFailed:    return "设置更新失败"
        case .verifyFailed(let msg):   return "验证失败: \(msg)"
        case .chatFailed(let msg):     return "请求失败: \(msg)"
        case .modelActionFailed(let msg): return "模型操作失败: \(msg)"
        case .notConfigured:           return "请先配置云端 API"
        case .invalidResponse:         return "网关返回无效响应"
        }
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

    func chat(_ req: ChatRequest) async throws -> AgentResponse {
        let url = baseURL.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(req)
        request.timeoutInterval = 60
        let started = Date()
        jlog("[GatewayClient] POST /chat input_mode=\(req.inputMode ?? "user_text") image=\(req.image != nil) message_chars=\((req.message ?? "").count)")
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
            return try decoder.decode(AgentResponse.self, from: data)
        } catch {
            let body = String(data: data.prefix(1000), encoding: .utf8) ?? "<non-utf8>"
            jlog("[GatewayClient] /chat decode failed: \(error); body=\(body)")
            throw error
        }
    }

    func getAvailableModels() async throws -> AvailableModelsResponse {
        try await getJSON(path: ["models", "available"])
    }

    func activateModel(_ req: ActivateModelRequest) async throws {
        let _: GatewayDetailResponse = try await postJSON(path: ["models", "activate"], body: req, timeout: 15)
    }

    func getLocalModels() async throws -> LocalModelsResponse {
        try await getJSON(path: ["models"])
    }

    func downloadModel(_ req: ModelDownloadRequest) async throws -> ModelDownloadStatus {
        try await postJSON(path: ["models", "download"], body: req, timeout: 15)
    }

    func downloadStatus() async throws -> ModelDownloadStatusResponse {
        try await getJSON(path: ["models", "download", "status"])
    }

    func loadLocalModel(_ req: ModelActionRequest) async throws {
        let _: GatewayDetailResponse = try await postJSON(path: ["models", "load"], body: req, timeout: 120)
    }

    func unloadLocalModel() async throws {
        let _: GatewayDetailResponse = try await postJSON(path: ["models", "unload"], body: EmptyBody(), timeout: 15)
    }

    func deleteLocalModel(modelId: String) async throws {
        var request = URLRequest(url: endpoint(["models", modelId]))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayError.modelActionFailed(detailMessage(from: data))
        }
    }

    func heartbeatTick(_ req: HeartbeatTickRequest) async throws -> HeartbeatTickResponse {
        try await postJSON(path: ["heartbeat", "tick"], body: req, timeout: 20)
    }

    func memoryStatus() async throws -> MemoryStatus {
        try await getJSON(path: ["memory"], timeout: 10)
    }

    func memoryFeedback(_ req: MemoryFeedbackRequest) async throws {
        let _: MemoryFeedbackResponse = try await postJSON(path: ["memory", "feedback"], body: req, timeout: 10)
    }

    func health() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let request = URLRequest(url: url, timeoutInterval: 5)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private struct EmptyBody: Encodable {}

    private func endpoint(_ path: [String]) -> URL {
        path.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private func getJSON<T: Decodable>(path: [String], timeout: TimeInterval = 10) async throws -> T {
        let request = URLRequest(url: endpoint(path), timeoutInterval: timeout)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayError.modelActionFailed(detailMessage(from: data))
        }
        return try decoder.decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        path: [String],
        body: Body,
        timeout: TimeInterval
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayError.modelActionFailed(detailMessage(from: data))
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func detailMessage(from data: Data) -> String {
        if let detail = (try? decoder.decode(GatewayDetailResponse.self, from: data))?.detail, !detail.isEmpty {
            return detail
        }
        return String(data: data.prefix(500), encoding: .utf8) ?? "未知错误"
    }
}
