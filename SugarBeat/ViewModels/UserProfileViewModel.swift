import Foundation
import Combine

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isBlocked = false

    func loadUser(userId: Int64) async {
        isLoading = true
        errorMessage = nil

        do {
            user = try await APIClient.shared.getUser(id: userId)
            posts = try await APIClient.shared.getUserPosts(userId: userId, sort: "desc")
        } catch {
            errorMessage = "Failed to load user: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func followUser(userId: Int64) async {
        do {
            try await APIClient.shared.followUser(userId: userId)
            await loadUser(userId: userId) // Refresh user data

            // Notify FeedView to refresh
            NotificationCenter.default.post(name: NSNotification.Name("FollowStatusChanged"), object: nil)
        } catch {
            errorMessage = "Failed to follow user: \(error.localizedDescription)"
        }
    }

    func unfollowUser(userId: Int64) async {
        do {
            try await APIClient.shared.unfollowUser(userId: userId)
            await loadUser(userId: userId) // Refresh user data

            // Notify FeedView to refresh
            NotificationCenter.default.post(name: NSNotification.Name("FollowStatusChanged"), object: nil)
        } catch {
            errorMessage = "Failed to unfollow user: \(error.localizedDescription)"
        }
    }

    func blockUser(userId: Int64) async {
        do {
            try await APIClient.shared.blockUser(userId: userId)

            // Set blocked state
            isBlocked = true

            // Clear posts
            posts = []

            // Notify FeedView to remove this user
            NotificationCenter.default.post(
                name: NSNotification.Name("UserBlocked"),
                object: nil,
                userInfo: ["blockedUserId": userId]
            )
        } catch {
            errorMessage = "Failed to block user: \(error.localizedDescription)"
        }
    }

    func deletePost(postId: Int64) async {
        do {
            try await APIClient.shared.deletePost(postId: postId)
            // Remove the deleted post from the local list
            posts.removeAll { $0.id == postId }
        } catch {
            errorMessage = "Failed to delete post: \(error.localizedDescription)"
        }
    }
}
