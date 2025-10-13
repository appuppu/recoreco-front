import Foundation

struct CreatePostRequest: Codable {
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
}
