import Foundation

struct Post: Codable, Identifiable {
    let id: Int64
    let user: User
    let appleMusicTrackId: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let artworkUrl: String?
    let previewUrl: String?
    let appleMusicUrl: String?
    let comment: String?
    let startTime: Double
    let endTime: Double
    let createdAt: Date
    let likeCount: Int?
    let isLiked: Bool?
    let commentCount: Int?
}
