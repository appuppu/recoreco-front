import Foundation
import SwiftUI

@MainActor
class LikeStateManager: ObservableObject {
    @Published private(set) var likedPostIds: Set<String> = []
    @Published private(set) var likeCounts: [String: Int] = [:]

    static let shared = LikeStateManager()

    private init() {}

    func initialize(postId: String, isLiked: Bool, count: Int) {
        // Only initialize if not already set (to preserve user changes)
        if likeCounts[postId] == nil {
            if isLiked {
                likedPostIds.insert(postId)
            }
            likeCounts[postId] = count
        }
    }

    func updateFromServer(postId: String, isLiked: Bool, count: Int) {
        // Force update from server data (for polling updates)
        if isLiked {
            likedPostIds.insert(postId)
        } else {
            likedPostIds.remove(postId)
        }
        likeCounts[postId] = count
    }

    func toggleLike(postId: String) {
        if likedPostIds.contains(postId) {
            likedPostIds.remove(postId)
            likeCounts[postId] = max(0, (likeCounts[postId] ?? 0) - 1)
        } else {
            likedPostIds.insert(postId)
            likeCounts[postId] = (likeCounts[postId] ?? 0) + 1
        }
    }

    func isLiked(_ postId: String) -> Bool {
        return likedPostIds.contains(postId)
    }

    func getLikeCount(_ postId: String) -> Int {
        return likeCounts[postId] ?? 0
    }

    func clear() {
        likedPostIds.removeAll()
        likeCounts.removeAll()
    }
}
