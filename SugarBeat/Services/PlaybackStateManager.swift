import Foundation
import SwiftUI

// Need to import Post model
struct PlayingPostInfo {
    let post: Post
    let user: User
}

@MainActor
class PlaybackStateManager: ObservableObject {
    @Published var currentlyPlayingPostId: String?
    @Published var currentlyPlayingUserId: String? // Which user's tab is playing
    @Published var currentlyPlayingInfo: PlayingPostInfo? // Currently playing post info

    static let shared = PlaybackStateManager()

    private init() {}

    func startPlayback(for postId: String, userId: String?, post: Post, user: User?) {
        currentlyPlayingPostId = postId
        currentlyPlayingUserId = userId
        if let user = user {
            currentlyPlayingInfo = PlayingPostInfo(post: post, user: user)
        }
    }

    func stopPlayback() {
        currentlyPlayingPostId = nil
        currentlyPlayingUserId = nil
        currentlyPlayingInfo = nil
    }

    func isPlaying(_ postId: String) -> Bool {
        return currentlyPlayingPostId == postId
    }

    func isPlayingInContext(postId: String, userId: String) -> Bool {
        return currentlyPlayingPostId == postId && currentlyPlayingUserId == userId
    }

    func updatePlaybackContext(userId: String) {
        currentlyPlayingUserId = userId
    }
}
