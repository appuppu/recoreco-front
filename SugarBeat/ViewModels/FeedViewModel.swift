import Foundation
import Combine

struct UserPosts: Identifiable {
    let id: Int64 // user ID
    let user: User
    var posts: [Post]
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var userPosts: [UserPosts] = []
    @Published var currentUserPosts: UserPosts?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get mutual follows feed
            posts = try await APIClient.shared.getMutualFollowsFeed()

            // Group posts by user
            let grouped = Dictionary(grouping: posts) { $0.user.id }

            // Create UserPosts for each user and sort by most recent post
            userPosts = grouped.map { userId, userPostsList in
                UserPosts(
                    id: userId,
                    user: userPostsList.first!.user,
                    posts: userPostsList.sorted { $0.createdAt > $1.createdAt }
                )
            }.sorted {
                $0.posts.first?.createdAt ?? Date.distantPast >
                $1.posts.first?.createdAt ?? Date.distantPast
            }

            // Load current user's posts
            if let currentUserId = APIClient.shared.currentUserId {
                await loadCurrentUserPosts(userId: currentUserId)
            }

        } catch {
            errorMessage = "フィードの読み込みに失敗しました: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func loadCurrentUserPosts(userId: Int64) async {
        do {
            let currentUserPostsList = try await APIClient.shared.getUserPosts(userId: userId)
            print("📥 Loaded \(currentUserPostsList.count) posts for user \(userId)")
            if !currentUserPostsList.isEmpty {
                currentUserPosts = UserPosts(
                    id: userId,
                    user: currentUserPostsList.first!.user,
                    posts: currentUserPostsList.sorted { $0.createdAt > $1.createdAt }
                )
            } else {
                currentUserPosts = nil
            }
        } catch {
            print("❌ Failed to load current user posts: \(error)")
            currentUserPosts = nil
        }
    }

    func refreshFeed() async {
        await loadFeed()
    }
}
