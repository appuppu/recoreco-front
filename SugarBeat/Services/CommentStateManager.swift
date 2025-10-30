import Foundation
import SwiftUI

@MainActor
class CommentStateManager: ObservableObject {
    @Published private(set) var commentCounts: [Int64: Int] = [:]

    static let shared = CommentStateManager()

    private init() {}

    func initialize(postId: Int64, count: Int) {
        // Only initialize if not already set (to preserve user changes)
        if commentCounts[postId] == nil {
            commentCounts[postId] = count
        }
    }

    func updateFromServer(postId: Int64, count: Int) {
        // Force update from server data (for polling updates)
        commentCounts[postId] = count
    }

    func incrementCount(postId: Int64) {
        commentCounts[postId] = (commentCounts[postId] ?? 0) + 1
    }

    func decrementCount(postId: Int64) {
        commentCounts[postId] = max(0, (commentCounts[postId] ?? 0) - 1)
    }

    func getCommentCount(_ postId: Int64) -> Int {
        return commentCounts[postId] ?? 0
    }

    func clear() {
        commentCounts.removeAll()
    }
}
