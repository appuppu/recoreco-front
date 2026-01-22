import Foundation
import SwiftUI

@MainActor
class CommentStateManager: ObservableObject {
    @Published private(set) var commentCounts: [String: Int] = [:]

    static let shared = CommentStateManager()

    private init() {}

    func initialize(postId: String, count: Int) {
        // Only initialize if not already set (to preserve user changes)
        if commentCounts[postId] == nil {
            commentCounts[postId] = count
        }
    }

    func updateFromServer(postId: String, count: Int) {
        // Force update from server data (for polling updates)
        commentCounts[postId] = count
    }

    func incrementCount(postId: String) {
        commentCounts[postId] = (commentCounts[postId] ?? 0) + 1
    }

    func decrementCount(postId: String) {
        commentCounts[postId] = max(0, (commentCounts[postId] ?? 0) - 1)
    }

    func getCommentCount(_ postId: String) -> Int {
        return commentCounts[postId] ?? 0
    }

    func clear() {
        commentCounts.removeAll()
    }
}
