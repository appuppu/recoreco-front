import Foundation
import FirebaseFirestore

struct User: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    let username: String
    let email: String?
    let displayName: String
    let profileImageUrl: String?
    let bio: String?
    let createdAt: Date
    let updatedAt: Date

    // Computed properties (not stored in Firestore) - 動的に取得
    var followingCount: Int? = nil
    var followerCount: Int? = nil
    var postCount: Int? = nil
    var isFollowing: Bool? = nil
    var isFollower: Bool? = nil
    var isMutual: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName
        case profileImageUrl
        case bio
        case createdAt
        case updatedAt
    }

    init(id: String? = nil,
         username: String,
         email: String?,
         displayName: String,
         profileImageUrl: String? = nil,
         bio: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.profileImageUrl = profileImageUrl
        self.bio = bio
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
