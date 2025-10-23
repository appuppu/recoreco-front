import Foundation

struct Comment: Codable, Identifiable {
    let id: Int64
    let postId: Int64
    let user: User
    let content: String
    let createdAt: Date
}

struct CreateCommentRequest: Codable {
    let postId: Int64
    let content: String
}
