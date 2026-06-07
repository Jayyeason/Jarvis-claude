import Foundation

extension ChatRequest {
    init(message: String, image: String?, inputMode: String, sessionId: String?) {
        self.init(
            message: message,
            image: image,
            inputMode: inputMode,
            sessionId: sessionId,
            formData: nil,
            userAction: nil,
            originalResult: nil,
            corrections: nil,
            selectedCandidateIds: nil
        )
    }
}

extension StoredAPIKey: Identifiable {}

extension ModelSource: Identifiable {
    var id: String { "\(source):\(providerId ?? ""):\(modelId)" }
    var isLocal: Bool { source == "local" }
}

extension LocalModelManifest: Identifiable {}

extension RecommendedLocalModel: Identifiable {
    var id: String { repoId }
}

extension ModelDownloadStatus: Identifiable {
    var id: String { modelId }
}
