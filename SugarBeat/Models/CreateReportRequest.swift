import Foundation

struct CreateReportRequest: Codable {
    let postId: String
    let reason: String
    let description: String?
}
