import Foundation
import FirebaseFirestore

enum ContentType: String, Codable {
    case music = "music"
    case youtube = "youtube"
    case website = "website"
}

enum ChannelType: String, Codable {
    case personal = "personal"  // Owner only can post
    case shared = "shared"      // All members can post
}

enum ChannelAccessType: String, Codable {
    case `public` = "public"    // Anyone can join
    case `private` = "private"  // For future expansion
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

    // Channel type and access
    var channelType: ChannelType
    var accessType: ChannelAccessType

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
        case channelType
        case accessType
    }

    init(id: String? = nil,
         userId: String,
         name: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         latestPostId: String? = nil,
         latestPostAt: Date? = nil,
         latestPostArtworkUrl: String? = nil,
         channelType: ChannelType = .personal,
         accessType: ChannelAccessType = .`public`) {
        self.id = id
        self.userId = userId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latestPostId = latestPostId
        self.latestPostAt = latestPostAt
        self.latestPostArtworkUrl = latestPostArtworkUrl
        self.channelType = channelType
        self.accessType = accessType
    }

    // Custom decoder for backward compatibility with existing channels
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        _id = try container.decode(DocumentID<String>.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        latestPostId = try container.decodeIfPresent(String.self, forKey: .latestPostId)
        latestPostAt = try container.decodeIfPresent(Date.self, forKey: .latestPostAt)
        latestPostArtworkUrl = try container.decodeIfPresent(String.self, forKey: .latestPostArtworkUrl)

        // Default to .personal for backward compatibility with existing channels
        channelType = try container.decodeIfPresent(ChannelType.self, forKey: .channelType) ?? .personal
        accessType = try container.decodeIfPresent(ChannelAccessType.self, forKey: .accessType) ?? .`public`
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
        // likeCount / commentCount are denormalized counters stored on the post
        // document. They are decoded with decodeIfPresent in the custom init below
        // (older posts may not have these fields → default to 0, no decode failure).
        case likeCount
        case commentCount
        // isLiked is per-viewer state, never stored.
    }

    // Custom decoder: likeCount / commentCount を decodeIfPresent で扱い、
    // フィールドが無い古い投稿でもデコード失敗しないようにする。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        _id = try container.decode(DocumentID<String>.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        appleMusicTrackId = try container.decodeIfPresent(String.self, forKey: .appleMusicTrackId)
        trackName = try container.decodeIfPresent(String.self, forKey: .trackName)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        albumName = try container.decodeIfPresent(String.self, forKey: .albumName)
        artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        artistImageUrl = try container.decodeIfPresent(String.self, forKey: .artistImageUrl)
        previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
        appleMusicUrl = try container.decodeIfPresent(String.self, forKey: .appleMusicUrl)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
        youtubeVideoId = try container.decodeIfPresent(String.self, forKey: .youtubeVideoId)
        youtubeThumbnailUrl = try container.decodeIfPresent(String.self, forKey: .youtubeThumbnailUrl)
        websiteUrl = try container.decodeIfPresent(String.self, forKey: .websiteUrl)
        websiteTitle = try container.decodeIfPresent(String.self, forKey: .websiteTitle)
        websiteDescription = try container.decodeIfPresent(String.self, forKey: .websiteDescription)
        websiteImageUrl = try container.decodeIfPresent(String.self, forKey: .websiteImageUrl)
        contentTitle = try container.decodeIfPresent(String.self, forKey: .contentTitle)
        contentDescription = try container.decodeIfPresent(String.self, forKey: .contentDescription)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // 非正規化カウンタ（古い投稿には存在しないため 0 をデフォルトにする）
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        // isLiked は閲覧者依存の状態なのでデコードしない
        isLiked = nil
    }

    // Custom encoder: likeCount / commentCount を含めて書き出す
    // （新規投稿はカウンタ 0 で初期化される）
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(channelId, forKey: .channelId)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(appleMusicTrackId, forKey: .appleMusicTrackId)
        try container.encodeIfPresent(trackName, forKey: .trackName)
        try container.encodeIfPresent(artistName, forKey: .artistName)
        try container.encodeIfPresent(albumName, forKey: .albumName)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encodeIfPresent(artistImageUrl, forKey: .artistImageUrl)
        try container.encodeIfPresent(previewUrl, forKey: .previewUrl)
        try container.encodeIfPresent(appleMusicUrl, forKey: .appleMusicUrl)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(youtubeVideoId, forKey: .youtubeVideoId)
        try container.encodeIfPresent(youtubeThumbnailUrl, forKey: .youtubeThumbnailUrl)
        try container.encodeIfPresent(websiteUrl, forKey: .websiteUrl)
        try container.encodeIfPresent(websiteTitle, forKey: .websiteTitle)
        try container.encodeIfPresent(websiteDescription, forKey: .websiteDescription)
        try container.encodeIfPresent(websiteImageUrl, forKey: .websiteImageUrl)
        try container.encodeIfPresent(contentTitle, forKey: .contentTitle)
        try container.encodeIfPresent(contentDescription, forKey: .contentDescription)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encode(commentCount, forKey: .commentCount)
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
