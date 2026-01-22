import Foundation

struct YouTubeUtils {
    /// Extract YouTube video ID from various YouTube URL formats
    /// Supports:
    /// - https://www.youtube.com/watch?v=VIDEO_ID
    /// - https://youtu.be/VIDEO_ID
    /// - https://m.youtube.com/watch?v=VIDEO_ID
    /// - https://youtube.com/embed/VIDEO_ID
    static func extractVideoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        let host = url.host?.lowercased() ?? ""
        let path = url.path

        // youtu.be format: https://youtu.be/VIDEO_ID
        if host.contains("youtu.be") {
            let videoId = path.replacingOccurrences(of: "/", with: "")
            return videoId.isEmpty ? nil : videoId
        }

        // youtube.com formats
        if host.contains("youtube.com") {
            // watch?v=VIDEO_ID format
            if path.contains("/watch"), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value {
                    return videoId
                }
            }

            // embed/VIDEO_ID format
            if path.contains("/embed/") {
                let components = path.components(separatedBy: "/")
                if let embedIndex = components.firstIndex(of: "embed"), embedIndex + 1 < components.count {
                    return components[embedIndex + 1]
                }
            }

            // v/VIDEO_ID format (legacy)
            if path.contains("/v/") {
                let components = path.components(separatedBy: "/")
                if let vIndex = components.firstIndex(of: "v"), vIndex + 1 < components.count {
                    return components[vIndex + 1]
                }
            }
        }

        return nil
    }

    /// Get YouTube thumbnail URL for a video ID
    /// Uses maxresdefault for best quality, falls back to hqdefault
    static func getThumbnailUrl(videoId: String, quality: ThumbnailQuality = .high) -> String {
        switch quality {
        case .maxRes:
            return "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"
        case .high:
            return "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
        case .medium:
            return "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
        case .standard:
            return "https://img.youtube.com/vi/\(videoId)/sddefault.jpg"
        case .default_:
            return "https://img.youtube.com/vi/\(videoId)/default.jpg"
        }
    }

    /// Get YouTube embed URL for WKWebView
    static func getEmbedUrl(videoId: String) -> String {
        return "https://www.youtube.com/embed/\(videoId)?playsinline=1&rel=0&modestbranding=1"
    }

    /// Validate if a URL is a YouTube URL
    static func isYouTubeUrl(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    enum ThumbnailQuality {
        case maxRes      // 1920x1080 (may not exist for all videos)
        case high        // 480x360
        case medium      // 320x180
        case standard    // 640x480
        case default_    // 120x90
    }
}
