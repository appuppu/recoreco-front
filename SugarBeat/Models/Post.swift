import Foundation
import FirebaseFirestore

enum ContentType: String, Codable {
    case music = "music"
    case youtube = "youtube"
    case website = "website"
}

// MARK: - Channel Model

struct Channel: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var latestPostId: String?
    var latestPostAt: Date?
    var latestPostArtworkUrl: String?

    // Computed properties (not stored in Firestore) - fetched dynamically from userId
    var isFollowing: Bool? = nil
    var followerCount: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case name
        case createdAt
        case updatedAt
        case latestPostId
        case latestPostAt
        case latestPostArtworkUrl
    }

    init(id: String? = nil,
         userId: String,
         name: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         latestPostId: String? = nil,
         latestPostAt: Date? = nil,
         latestPostArtworkUrl: String? = nil) {
        self.id = id
        self.userId = userId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latestPostId = latestPostId
        self.latestPostAt = latestPostAt
        self.latestPostArtworkUrl = latestPostArtworkUrl
    }
}

struct Post: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String

    // Channel information
    let channelId: String?

    // Content type (optional for backward compatibility with old posts)
    let contentType: String?

    // Music-specific fields
    let appleMusicTrackId: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let artworkUrl: String?
    let artistImageUrl: String?
    let previewUrl: String?
    let appleMusicUrl: String?
    let startTime: Double?
    let endTime: Double?

    // YouTube-specific fields
    let youtubeVideoId: String?
    let youtubeThumbnailUrl: String?

    // Website-specific fields
    let websiteUrl: String?
    let websiteTitle: String?
    let websiteDescription: String?
    let websiteImageUrl: String?

    // Common fields
    let contentTitle: String? // Generic title for all content types
    let contentDescription: String? // Generic description
    let comment: String?
    let createdAt: Date
    let updatedAt: Date

    // Computed properties (not stored in Firestore) - fetched dynamically
    var isLiked: Bool? = nil
    var likeCount: Int = 0
    var commentCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case channelId
        case contentType
        case appleMusicTrackId
        case trackName
        case artistName
        case albumName
        case artworkUrl
        case artistImageUrl
        case previewUrl
        case appleMusicUrl
        case startTime
        case endTime
        case youtubeVideoId
        case youtubeThumbnailUrl
        case websiteUrl
        case websiteTitle
        case websiteDescription
        case websiteImageUrl
        case contentTitle
        case contentDescription
        case comment
        case createdAt
        case updatedAt
        // likeCount and commentCount are NOT included here
        // because they are computed properties managed in-memory
    }

    // Music post initializer
    init(id: String? = nil,
         userId: String,
         channelId: String? = nil,
         appleMusicTrackId: String,
         trackName: String,
         artistName: String,
         albumName: String? = nil,
         artworkUrl: String? = nil,
         artistImageUrl: String? = nil,
         previewUrl: String? = nil,
         appleMusicUrl: String? = nil,
         comment: String? = nil,
         startTime: Double,
         endTime: Double,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.channelId = channelId
        self.contentType = ContentType.music.rawValue
        self.appleMusicTrackId = appleMusicTrackId
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.artworkUrl = artworkUrl
        self.artistImageUrl = artistImageUrl
        self.previewUrl = previewUrl
        self.appleMusicUrl = appleMusicUrl
        self.startTime = startTime
        self.endTime = endTime
        self.youtubeVideoId = nil
        self.youtubeThumbnailUrl = nil
        self.websiteUrl = nil
        self.websiteTitle = nil
        self.websiteDescription = nil
        self.websiteImageUrl = nil
        self.contentTitle = trackName
        self.contentDescription = artistName
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Generic content initializer
    init(id: String? = nil,
         userId: String,
         channelId: String? = nil,
         contentType: ContentType,
         appleMusicTrackId: String? = nil,
         trackName: String? = nil,
         artistName: String? = nil,
         albumName: String? = nil,
         artworkUrl: String? = nil,
         artistImageUrl: String? = nil,
         previewUrl: String? = nil,
         appleMusicUrl: String? = nil,
         startTime: Double? = nil,
         endTime: Double? = nil,
         youtubeVideoId: String? = nil,
         youtubeThumbnailUrl: String? = nil,
         websiteUrl: String? = nil,
         websiteTitle: String? = nil,
         websiteDescription: String? = nil,
         websiteImageUrl: String? = nil,
         contentTitle: String? = nil,
         contentDescription: String? = nil,
         comment: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.channelId = channelId
        self.contentType = contentType.rawValue
        self.appleMusicTrackId = appleMusicTrackId
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.artworkUrl = artworkUrl
        self.artistImageUrl = artistImageUrl
        self.previewUrl = previewUrl
        self.appleMusicUrl = appleMusicUrl
        self.startTime = startTime
        self.endTime = endTime
        self.youtubeVideoId = youtubeVideoId
        self.youtubeThumbnailUrl = youtubeThumbnailUrl
        self.websiteUrl = websiteUrl
        self.websiteTitle = websiteTitle
        self.websiteDescription = websiteDescription
        self.websiteImageUrl = websiteImageUrl
        self.contentTitle = contentTitle
        self.contentDescription = contentDescription
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
