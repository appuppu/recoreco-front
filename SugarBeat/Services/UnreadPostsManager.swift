import Foundation
import SwiftUI

@MainActor
class UnreadPostsManager: ObservableObject {
    static let shared = UnreadPostsManager()

    private let userDefaults = UserDefaults.standard
    private let readPostsKey = "readPostIds"

    @Published private var readPostIds: Set<String> = []

    private init() {
        loadReadPosts()
    }

    private func loadReadPosts() {
        if let data = userDefaults.data(forKey: readPostsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            readPostIds = decoded
        }
    }

    private func saveReadPosts() {
        if let encoded = try? JSONEncoder().encode(readPostIds) {
            userDefaults.set(encoded, forKey: readPostsKey)
        }
    }

    func isUnread(_ postId: String?) -> Bool {
        guard let postId = postId else { return false }
        return !readPostIds.contains(postId)
    }

    func markAsRead(_ postId: String) {
        readPostIds.insert(postId)
        saveReadPosts()
    }

    func hasUnreadPosts(in posts: [Post]) -> Bool {
        return posts.contains { isUnread($0.id) }
    }
}

@MainActor
class ScreenshotModeManager: ObservableObject {
    @Published var isScreenshotMode = false

    static let shared = ScreenshotModeManager()

    private init() {}
}
