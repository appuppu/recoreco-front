import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var isBlocked = false // 操作ユーザーがブロックしている
    @Published var isBlockedBy = false // 操作ユーザーがブロックされている

    private var lastDocument: DocumentSnapshot?
    private var hasMorePosts = true

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

            // Reset pagination state on initial load
            lastDocument = nil
            hasMorePosts = true

            let (fetchedPosts, lastDoc) = try await FirestorePostManager.shared.getUserPosts(userId: userId, limit: 20)
            // 全ての投稿を表示（channelIdフィルタリングを削除）
            posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
            lastDocument = lastDoc
            hasMorePosts = fetchedPosts.count >= 20
            print("🔍 [UserProfileViewModel] Loaded \(posts.count) posts, hasMore: \(hasMorePosts)")
        } catch {
            errorMessage = "ユーザー情報を取得できませんでした"
            print("❌ Failed to load user: \(error)")
        }

        isLoading = false
    }

    /// フォロー/解除後にフォロー数・フォロワー数だけを最新化する（キャッシュを使わない）
    func refreshCounts(userId: String) async {
        if let fresh = try? await FirestoreUserManager.shared.getUser(userId: userId, useCache: false, fetchCounts: true) {
            user = fresh
        }
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

    func loadMorePosts(userId: String) async {
        guard !isLoadingMore, hasMorePosts, let lastDoc = lastDocument else {
            print("⏭️ [UserProfileViewModel] Skip loadMore - isLoadingMore: \(isLoadingMore), hasMore: \(hasMorePosts), lastDoc: \(lastDocument != nil)")
            return
        }

        isLoadingMore = true
        print("📄 [UserProfileViewModel] Loading more posts from lastDocument...")

        do {
            let (fetchedPosts, lastDoc) = try await FirestorePostManager.shared.getUserPosts(userId: userId, limit: 20, lastDocument: lastDoc)

            // Append new posts to existing posts
            posts.append(contentsOf: fetchedPosts.sorted { $0.createdAt > $1.createdAt })
            lastDocument = lastDoc
            hasMorePosts = fetchedPosts.count >= 20

            print("✅ [UserProfileViewModel] Loaded \(fetchedPosts.count) more posts. Total: \(posts.count), hasMore: \(hasMorePosts)")
        } catch {
            print("❌ [UserProfileViewModel] Failed to load more posts: \(error)")
        }

        isLoadingMore = false
    }
}
