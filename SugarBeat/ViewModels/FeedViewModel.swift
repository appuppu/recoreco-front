import Foundation
import Combine

struct UserPosts: Identifiable {
    let id: Int64 // user ID
    let user: User
    var posts: [Post]
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var allUserPosts: [UserPosts] = [] // All users including self, sorted by latest post
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let currentUserId = APIClient.shared.currentUserId else {
                errorMessage = "ユーザーIDが取得できません"
                isLoading = false
                return
            }

            // Load current user's posts
            let currentUserPostsList = try await APIClient.shared.getUserPosts(userId: currentUserId)
            print("📥 Loaded \(currentUserPostsList.count) posts for current user \(currentUserId)")

            // Get mutual follows feed
            let mutualFollowsPosts = try await APIClient.shared.getMutualFollowsFeed()
            print("📥 Loaded \(mutualFollowsPosts.count) posts from mutual follows")

            // Combine current user posts and mutual follows posts
            let allPosts = currentUserPostsList + mutualFollowsPosts

            // Group posts by user
            let grouped = Dictionary(grouping: allPosts) { $0.user.id }

            // Create UserPosts for each user and sort by most recent post
            allUserPosts = grouped.map { userId, userPostsList in
                UserPosts(
                    id: userId,
                    user: userPostsList.first!.user,
                    posts: userPostsList.sorted { $0.createdAt > $1.createdAt }
                )
            }.sorted {
                // Sort by latest post timestamp
                $0.posts.first?.createdAt ?? Date.distantPast >
                $1.posts.first?.createdAt ?? Date.distantPast
            }

            // Move current user to the front
            if let currentUserIndex = allUserPosts.firstIndex(where: { $0.id == currentUserId }) {
                let currentUser = allUserPosts.remove(at: currentUserIndex)
                allUserPosts.insert(currentUser, at: 0)
            }

            print("📊 Total users in feed: \(allUserPosts.count)")

        } catch {
            // Ignore cancellation errors (happens when quickly switching between users)
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("⚠️ Feed load cancelled (normal when switching users quickly)")
                return
            }

            errorMessage = "フィードの読み込みに失敗しました: \(error.localizedDescription)"
            print("❌ Failed to load feed: \(error)")
        }

        isLoading = false
    }

    func refreshFeed() async {
        await loadFeed()
    }
}
