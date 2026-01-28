import Foundation
import Combine
import FirebaseAuth

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isBlocked = false // 操作ユーザーがブロックしている
    @Published var isBlockedBy = false // 操作ユーザーがブロックされている

    init() {
        // 投稿削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let postId = notification.userInfo?["postId"] as? String {
                    self?.posts.removeAll { $0.id == postId }
                }
            }
        }

        // ユーザーブロック通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.userBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let blockedUserId = notification.userInfo?["blockedUserId"] as? String {
                    // 表示中のユーザーがブロックされた場合
                    if self?.user?.id == blockedUserId {
                        self?.isBlocked = true
                        self?.posts = []
                        print("🚫 UserProfileViewModel: User was blocked, cleared posts")
                    }
                }
            }
        }
    }

    func loadUser(userId: String) async {
        print("🔍 [UserProfileViewModel] loadUser called for userId: \(userId)")
        isLoading = true
        errorMessage = nil
        isBlocked = false
        isBlockedBy = false

        do {
            // Check blocking status
            if Auth.auth().currentUser?.uid != nil {
                // 操作ユーザーがブロックしている
                let isUserBlocked = try await FirestoreBlockManager.shared.isUserBlocked(userId: userId)
                if isUserBlocked {
                    print("🔍 [UserProfileViewModel] User is blocked by current user: \(userId)")
                    isBlocked = true
                    isLoading = false
                    return
                }

                // 操作ユーザーがブロックされている
                let isUserBlockedBy = try await FirestoreBlockManager.shared.isBlockedBy(userId: userId)
                if isUserBlockedBy {
                    print("🔍 [UserProfileViewModel] Current user is blocked by: \(userId)")
                    isBlockedBy = true
                    errorMessage = "ユーザーが見つかりませんでした。"
                    isLoading = false
                    return
                }
            }

            user = try await FirestoreUserManager.shared.getUser(userId: userId, fetchCounts: true)
            print("✅ [UserProfileViewModel] Loaded user: \(user?.username ?? "unknown")")

            let (fetchedPosts, _) = try await FirestorePostManager.shared.getUserPosts(userId: userId, limit: 50)
            // チャンネルに紐づく投稿のみをフィルタリング
            let channelPosts = fetchedPosts.filter { $0.channelId != nil }
            posts = channelPosts.sorted { $0.createdAt > $1.createdAt }
            print("🔍 [UserProfileViewModel] Loaded \(posts.count) channel posts (out of \(fetchedPosts.count) total)")
        } catch {
            errorMessage = "ユーザー情報を取得できませんでした"
            print("❌ Failed to load user: \(error)")
        }

        isLoading = false
    }

    func blockUser(userId: String) async {
        do {
            try await FirestoreBlockManager.shared.blockUser(userId: userId)
            print("🚫 Block succeeded for userId: \(userId)")

            // Set blocked state
            isBlocked = true

            // Clear posts
            posts = []

            // 通知を発行して即座に反映（@MainActorなのでメインスレッドで実行される）
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.userBlocked,
                object: nil,
                userInfo: ["blockedUserId": userId]
            )
            print("🚫 Block notification posted for blockedUserId: \(userId)")
        } catch {
            errorMessage = "ブロックに失敗しました"
            print("❌ Failed to block user: \(error)")
        }
    }

    func deletePost(postId: String) async {
        do {
            try await FirestorePostManager.shared.deletePost(postId: postId)
            // Remove the deleted post from the local list
            posts.removeAll { $0.id == postId }
            // 通知を発行して即座に反映
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.postDeleted,
                object: nil,
                userInfo: ["postId": postId]
            )
        } catch {
            errorMessage = "削除に失敗しました"
            print("❌ Failed to delete post: \(error)")
        }
    }

    func loadChannels(userId: String) async {
        do {
            // Load both own channels and followed channels
            let ownChannels = try await FirestoreChannelManager.shared.getUserChannels(userId: userId)
            let followedChannels = try await FirestoreChannelManager.shared.getFollowedChannels(userId: userId)

            // Merge and remove duplicates
            var allChannels = ownChannels
            for followedChannel in followedChannels {
                if !allChannels.contains(where: { $0.id == followedChannel.id }) {
                    allChannels.append(followedChannel)
                }
            }

            channels = allChannels
            print("✅ Loaded \(allChannels.count) channels for user: \(userId) (own: \(ownChannels.count), followed: \(followedChannels.count))")
        } catch {
            errorMessage = "チャンネルの取得に失敗しました"
            print("❌ Failed to load channels: \(error)")
        }
    }
}
