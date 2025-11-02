import Foundation
import SwiftUI

@MainActor
class PlaybackStateManager: ObservableObject {
    @Published var currentlyPlayingPostId: Int64?
    @Published var currentlyPlayingUserId: Int64? // Which user's tab is playing

    static let shared = PlaybackStateManager()

    private init() {}

    func startPlayback(for postId: Int64, userId: Int64) {
        currentlyPlayingPostId = postId
        currentlyPlayingUserId = userId
    }

    func stopPlayback() {
        currentlyPlayingPostId = nil
        currentlyPlayingUserId = nil
    }

    func isPlaying(_ postId: Int64) -> Bool {
        return currentlyPlayingPostId == postId
    }

    func isPlayingInContext(postId: Int64, userId: Int64) -> Bool {
        return currentlyPlayingPostId == postId && currentlyPlayingUserId == userId
    }
}
