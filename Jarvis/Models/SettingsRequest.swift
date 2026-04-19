import Foundation

struct SettingsRequest: Codable {
    let providerId: String
    let modelId: String
    let apiKey: String
    let baseUrl: String?
    let awsAccessKey: String?
    let awsSecretKey: String?
    let region: String?

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case modelId = "model_id"
        case apiKey = "api_key"
        case baseUrl = "base_url"
        case awsAccessKey = "aws_access_key"
        case awsSecretKey = "aws_secret_key"
        case region
    }
}
