import Foundation
import FirebaseFirestore

struct Notification: Codable, Identifiable {
    @DocumentID var id: String?
    let recipientId: String
    let senderId: String
    let senderUsername: String
    let senderDisplayName: String
    let senderProfileImageUrl: String?
    let type: NotificationType
    let postId: String?
    let artworkUrl: String?
    let channelName: String?
    let channelType: String? // "shared" or "personal"
    let isRead: Bool
    let createdAt: Date

    enum NotificationType: String, Codable {
        case like
        case comment
        case channelFollow
        case follow // ユーザーフォロー
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recipientId
        case senderId
        case senderUsername
        case senderDisplayName
        case senderProfileImageUrl
        case type
        case postId
        case artworkUrl
        case channelName
        case channelType
        case isRead
        case createdAt
    }

    init(id: String? = nil,
         recipientId: String,
         senderId: String,
         senderUsername: String,
         senderDisplayName: String,
         senderProfileImageUrl: String? = nil,
         type: NotificationType,
         postId: String? = nil,
         artworkUrl: String? = nil,
         channelName: String? = nil,
         channelType: String? = nil,
         isRead: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.recipientId = recipientId
        self.senderId = senderId
        self.senderUsername = senderUsername
        self.senderDisplayName = senderDisplayName
        self.senderProfileImageUrl = senderProfileImageUrl
        self.type = type
        self.postId = postId
        self.artworkUrl = artworkUrl
        self.channelName = channelName
        self.channelType = channelType
        self.isRead = isRead
        self.createdAt = createdAt
    }

    // Helper: Create from User
    init(from sender: User,
         recipientId: String,
         type: NotificationType,
         postId: String? = nil,
         artworkUrl: String? = nil,
         channelName: String? = nil,
         channelType: String? = nil) {
        self.init(
            recipientId: recipientId,
            senderId: sender.id ?? "",
            senderUsername: sender.username,
            senderDisplayName: sender.displayName,
            senderProfileImageUrl: sender.profileImageUrl,
            type: type,
            postId: postId,
            artworkUrl: artworkUrl,
            channelName: channelName,
            channelType: channelType
        )
    }
}

// MARK: - Notification Names

extension Foundation.Notification.Name {
    static let postCreated = Foundation.Notification.Name("postCreated")
    static let postDeleted = Foundation.Notification.Name("postDeleted")
    static let userBlocked = Foundation.Notification.Name("userBlocked")
}
