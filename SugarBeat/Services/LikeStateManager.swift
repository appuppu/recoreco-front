import Foundation
import SwiftUI

@MainActor
class LikeStateManager: ObservableObject {
    @Published private(set) var likedPostIds: Set<Int64> = []
    @Published private(set) var likeCounts: [Int64: Int] = [:]

    static let shared = LikeStateManager()

    private init() {}

    func initialize(postId: Int64, isLiked: Bool, count: Int) {
        // Only initialize if not already set (to preserve user changes)
        if likeCounts[postId] == nil {
            if isLiked {
                likedPostIds.insert(postId)
            }
            likeCounts[postId] = count
        }
    }

    func toggleLike(postId: Int64) {
        if likedPostIds.contains(postId) {
            likedPostIds.remove(postId)
            likeCounts[postId] = max(0, (likeCounts[postId] ?? 0) - 1)
        } else {
            likedPostIds.insert(postId)
            likeCounts[postId] = (likeCounts[postId] ?? 0) + 1
        }
    }

    func isLiked(_ postId: Int64) -> Bool {
        return likedPostIds.contains(postId)
    }

    func getLikeCount(_ postId: Int64) -> Int {
        return likeCounts[postId] ?? 0
    }

    func clear() {
        likedPostIds.removeAll()
        likeCounts.removeAll()
    }
}
