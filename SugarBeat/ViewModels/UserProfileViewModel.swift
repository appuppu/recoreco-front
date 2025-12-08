import Foundation
import Combine

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isBlocked = false

    init() {
        // 投稿削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let postId = notification.userInfo?["postId"] as? Int64 {
                    self?.posts.removeAll { $0.id == postId }
                }
            }
        }
    }

    func loadUser(userId: Int64) async {
        isLoading = true
        errorMessage = nil

        do {
            user = try await APIClient.shared.getUser(id: userId)
            posts = try await APIClient.shared.getUserPosts(userId: userId, sort: "desc")
        } catch {
            // Check for blocked user error
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("not accessible") || errorString.contains("blocked") {
                isBlocked = true
                errorMessage = nil // blockedViewで表示するのでエラーメッセージは不要
            } else {
                errorMessage = "ユーザー情報を取得できませんでした"
            }
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
            print("🚫 Block succeeded for userId: \(userId)")

            // Set blocked state
            isBlocked = true

            // Clear posts
            posts = []

            // 通知を発行して即座に反映（@MainActorなのでメインスレッドで実行される）
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.userBlocked,
                object: nil,
                userInfo: ["userId": userId]
            )
            print("🚫 Block notification posted for userId: \(userId)")
        } catch {
            errorMessage = "ブロックに失敗しました"
            print("❌ Failed to block user: \(error)")
        }
    }

    func deletePost(postId: Int64) async {
        do {
            try await APIClient.shared.deletePost(postId: postId)
            // Remove the deleted post from the local list
            posts.removeAll { $0.id == postId }
            // 通知を発行して即座に反映
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.postDeleted,
                object: nil,
                userInfo: ["postId": postId]
            )
        } catch {
            errorMessage = "Failed to delete post: \(error.localizedDescription)"
        }
    }
}
