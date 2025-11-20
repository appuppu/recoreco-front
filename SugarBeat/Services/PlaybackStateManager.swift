import Foundation
import SwiftUI

// Need to import Post model
struct PlayingPostInfo {
    let post: Post
    let user: User
}

@MainActor
class PlaybackStateManager: ObservableObject {
    @Published var currentlyPlayingPostId: Int64?
    @Published var currentlyPlayingUserId: Int64? // Which user's tab is playing
    @Published var currentlyPlayingInfo: PlayingPostInfo? // Currently playing post info

    static let shared = PlaybackStateManager()

    private init() {}

    func startPlayback(for postId: Int64, userId: Int64, post: Post, user: User) {
        currentlyPlayingPostId = postId
        currentlyPlayingUserId = userId
        currentlyPlayingInfo = PlayingPostInfo(post: post, user: user)
    }

    func stopPlayback() {
        currentlyPlayingPostId = nil
        currentlyPlayingUserId = nil
        currentlyPlayingInfo = nil
    }

    func isPlaying(_ postId: Int64) -> Bool {
        return currentlyPlayingPostId == postId
    }

    func isPlayingInContext(postId: Int64, userId: Int64) -> Bool {
        return currentlyPlayingPostId == postId && currentlyPlayingUserId == userId
    }

    func updatePlaybackContext(userId: Int64) {
        currentlyPlayingUserId = userId
    }
}
