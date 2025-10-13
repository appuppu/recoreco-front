import Foundation
import Combine

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadUser(userId: Int64) async {
        isLoading = true
        errorMessage = nil

        do {
            user = try await APIClient.shared.getUser(id: userId)
            posts = try await APIClient.shared.getUserPosts(userId: userId)
        } catch {
            errorMessage = "Failed to load user: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func followUser(userId: Int64) async {
        do {
            try await APIClient.shared.followUser(userId: userId)
            await loadUser(userId: userId) // Refresh user data
        } catch {
            errorMessage = "Failed to follow user: \(error.localizedDescription)"
        }
    }

    func unfollowUser(userId: Int64) async {
        do {
            try await APIClient.shared.unfollowUser(userId: userId)
            await loadUser(userId: userId) // Refresh user data
        } catch {
            errorMessage = "Failed to unfollow user: \(error.localizedDescription)"
        }
    }
}
