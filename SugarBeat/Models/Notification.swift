import Foundation

struct Notification: Codable, Identifiable {
    let id: Int64
    let sender: NotificationUser
    let type: String
    let postId: Int64?
    let postOwnerId: Int64?
    let artworkUrl: String?
    let isRead: Bool
    let createdAt: Date
}

struct NotificationUser: Codable {
    let id: Int64
    let username: String
    let displayName: String
    let profileImageUrl: String?
}
