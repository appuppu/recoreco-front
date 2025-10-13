import Foundation
import SwiftUI

@MainActor
class PlaybackStateManager: ObservableObject {
    @Published var currentlyPlayingPostId: Int64?

    static let shared = PlaybackStateManager()

    private init() {}

    func startPlayback(for postId: Int64) {
        currentlyPlayingPostId = postId
    }

    func stopPlayback() {
        currentlyPlayingPostId = nil
    }

    func isPlaying(_ postId: Int64) -> Bool {
        return currentlyPlayingPostId == postId
    }
}
