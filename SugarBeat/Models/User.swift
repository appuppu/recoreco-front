import Foundation

struct User: Codable, Identifiable {
    let id: Int64
    let username: String
    let email: String?
    let displayName: String
    let profileImageUrl: String?
    let bio: String?
    let createdAt: Date?
    let isFollowing: Bool?
    let isFollower: Bool?
    let isMutual: Bool?
}
