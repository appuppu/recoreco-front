import Foundation

struct CreateCommentRequest: Codable {
    let postId: String
    let content: String
}
