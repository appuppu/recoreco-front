import Foundation
import FirebaseFirestore

struct Comment: Codable, Identifiable {
    @DocumentID var id: String?
    let postId: String
    let userId: String
    let username: String
    let userDisplayName: String
    var userProfileImageUrl: String?
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let parentCommentId: String?  // 返信先コメントID（nilの場合は親コメント）
    var replyCount: Int = 0  // 返信数（動的に取得、Firestoreには保存しない）
    var likeCount: Int = 0  // いいね数（動的に取得、Firestoreには保存しない）
    var isLiked: Bool = false  // 現在のユーザーがいいねしているか（動的に取得、Firestoreには保存しない）

    enum CodingKeys: String, CodingKey {
        case id
        case postId
        case userId
        case username
        case userDisplayName
        case userProfileImageUrl
        case content
        case createdAt
        case updatedAt
        case parentCommentId
        // replyCount, likeCount, isLikedは除外（動的に取得するため）
    }

    // 既存データとの互換性のためのカスタムDecoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        _id = try container.decode(DocumentID<String>.self, forKey: .id)
        postId = try container.decode(String.self, forKey: .postId)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decode(String.self, forKey: .username)
        userDisplayName = try container.decode(String.self, forKey: .userDisplayName)
        userProfileImageUrl = try container.decodeIfPresent(String.self, forKey: .userProfileImageUrl)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        // replyCount, likeCount, isLikedはデフォルト値で初期化（後で動的に設定）
        replyCount = 0
        likeCount = 0
        isLiked = false
    }

    init(id: String? = nil,
         postId: String,
         userId: String,
         username: String,
         userDisplayName: String,
         userProfileImageUrl: String? = nil,
         content: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         parentCommentId: String? = nil,
         replyCount: Int = 0,
         likeCount: Int = 0,
         isLiked: Bool = false) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.username = username
        self.userDisplayName = userDisplayName
        self.userProfileImageUrl = userProfileImageUrl
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentCommentId = parentCommentId
        self.replyCount = replyCount
        self.likeCount = likeCount
        self.isLiked = isLiked
    }

    // Helper: Create from User
    init(from user: User, postId: String, content: String, parentCommentId: String? = nil) {
        // NOTE: userProfileImageUrlはFirestoreに保存しない（動的に取得するため）
        self.init(
            postId: postId,
            userId: user.id ?? "",
            username: user.username,
            userDisplayName: user.displayName,
            userProfileImageUrl: nil, // Firestoreには保存しない
            content: content,
            parentCommentId: parentCommentId
        )
    }
}
