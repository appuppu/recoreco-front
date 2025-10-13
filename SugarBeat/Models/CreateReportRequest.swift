import Foundation

struct CreateReportRequest: Codable {
    let postId: Int64
    let reason: String
    let description: String?
}
