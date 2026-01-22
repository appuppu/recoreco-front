import Foundation
import FirebaseFirestore

struct Report: Codable, Identifiable {
    @DocumentID var id: String?
    let reporterId: String
    let type: ReportType
    let targetId: String // postId or commentId
    let reason: String
    let description: String?
    let status: ReportStatus
    let createdAt: Date

    enum ReportType: String, Codable {
        case post
        case comment
        case channel
    }

    enum ReportStatus: String, Codable {
        case pending
        case reviewed
        case resolved
    }

    enum CodingKeys: String, CodingKey {
        case id
        case reporterId
        case type
        case targetId
        case reason
        case description
        case status
        case createdAt
    }

    init(id: String? = nil,
         reporterId: String,
         type: ReportType,
         targetId: String,
         reason: String,
         description: String? = nil,
         status: ReportStatus = .pending,
         createdAt: Date = Date()) {
        self.id = id
        self.reporterId = reporterId
        self.type = type
        self.targetId = targetId
        self.reason = reason
        self.description = description
        self.status = status
        self.createdAt = createdAt
    }
}
