import Foundation

struct MusicSearchResponse: Codable {
    let results: MusicSearchResults
}

struct MusicSearchResults: Codable {
    let songs: MusicSongsData?
}

struct MusicSongsData: Codable {
    let data: [AppleMusicSong]
}

struct AppleMusicSong: Codable, Identifiable {
    let id: String
    let type: String
    let attributes: SongAttributes
}

struct SongAttributes: Codable {
    let name: String
    let artistName: String
    let albumName: String?
    let artwork: Artwork?
    let url: String?
    let previews: [Preview]?
    let durationInMillis: Int?

    var duration: Double? {
        guard let millis = durationInMillis else { return nil }
        return Double(millis) / 1000.0
    }
}

struct Artwork: Codable {
    let width: Int?
    let height: Int?
    let url: String

    func artworkURL(width: Int, height: Int) -> String {
        // Apple Music API returns URL template like: https://.../image.jpg/{w}x{h}bb.jpg
        // Replace {w} and {h} with desired dimensions
        let urlWithPlaceholders = url
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")

        // If URL doesn't have placeholders, append dimensions
        if urlWithPlaceholders == url && !url.contains("\(width)x\(height)") {
            // Remove trailing slash if exists
            let baseUrl = url.hasSuffix("/") ? String(url.dropLast()) : url
            return "\(baseUrl)/\(width)x\(height)bb.jpg"
        }

        return urlWithPlaceholders
    }
}

struct Preview: Codable {
    let url: String
}
