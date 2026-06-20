import SwiftUI
import FirebaseAuth

/// フォロー中タブ - フォローしているユーザーの投稿を縦スワイプ表示
struct FollowingFeedView: View {
    var reloadTrigger: Int = 0
    @StateObject private var viewModel = FollowingFeedViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingLoginSheet = false
    @State private var showingLoginPrompt = false
    @State private var scrollToTopTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if !authManager.isAuthenticated {
                    // Not logged in
                    LoginRequiredView(showingLoginSheet: $showingLoginSheet, message: "フォロー中の投稿を見るには\nログインしてください")
                } else if viewModel.posts.isEmpty && !viewModel.isLoading {
                    // No posts from followed users
                    emptyState
                } else {
                    ScrollableFeedView(
                        posts: viewModel.posts,
                        isLoading: viewModel.isLoading,
                        isLoadingMore: viewModel.isLoadingMore,
                        onLoadMore: {
                            await viewModel.loadMorePosts()
                        },
                        onRefresh: {
                            await viewModel.refreshPosts()
                        },
                        showingLoginPrompt: $showingLoginPrompt,
                        scrollToTopTrigger: scrollToTopTrigger
                    )
                }
            }
            .navigationBarHidden(true)
        }
        .onChange(of: reloadTrigger) { _ in
            // タブ再タップ: 一番上へスクロールするだけ（更新はしない）
            scrollToTopTrigger += 1
        }
        .task {
            if authManager.isAuthenticated && viewModel.posts.isEmpty {
                await viewModel.loadInitialPosts()
            }
        }
        .onChange(of: authManager.isAuthenticated) { isAuthenticated in
            if isAuthenticated && viewModel.posts.isEmpty {
                Task {
                    await viewModel.loadInitialPosts()
                }
            }
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            LoginView()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("フォロー中のユーザーの\n投稿がありません")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Text("ユーザーをフォローして\n投稿を見よう")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - ViewModel
@MainActor
class FollowingFeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMorePosts = true

    private var allPosts: [Post] = []
    private let batchSize = 20

    init() {
        // Listen to post creation notifications
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshPosts()
            }
        }

        // Listen to user block notifications
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.userBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let blockedUserId = notification.userInfo?["blockedUserId"] as? String {
                Task { @MainActor in
                    // Remove posts from blocked user immediately
                    self?.allPosts.removeAll { $0.userId == blockedUserId }
                    self?.posts.removeAll { $0.userId == blockedUserId }
                    print("🚫 Removed posts from blocked user: \(blockedUserId)")
                }
            }
        }
    }

    func loadInitialPosts() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                isLoading = false
                return
            }

            // Get list of followed user IDs, plus the current user themselves
            // （フォロー中の人 + 自分の投稿を表示する）
            let followedUserIds = try await FirestoreFollowManager.shared.getFollowingIds(userId: currentUserId)
            let feedUserIds = Array(Set(followedUserIds + [currentUserId]))

            // Get posts from followed users + self
            let (fetchedPosts, _) = try await FirestorePostManager.shared.getFollowingFeed(
                userIds: feedUserIds,
                limit: 100
            )

            // Filter out blocked users
            let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []
            allPosts = fetchedPosts.filter { !blockedUserIds.contains($0.userId) }

            // Sort by newest first
            allPosts.sort { $0.createdAt > $1.createdAt }

            // Load first batch
            posts = Array(allPosts.prefix(batchSize))
            hasMorePosts = allPosts.count > batchSize

            // 投稿者をまとめて事前取得してキャッシュを温める（各カードの個別リクエストを抑制）
            let authorIds = Array(Set(posts.map { $0.userId }))
            _ = try? await FirestoreUserManager.shared.getUsers(userIds: authorIds)

            print("✅ Loaded \(posts.count) posts from \(followedUserIds.count) followed users (newest first)")
        } catch {
            print("❌ Failed to load following feed: \(error)")
        }

        isLoading = false
    }

    func loadMorePosts() async {
        guard hasMorePosts, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true

        let currentCount = posts.count
        let nextBatch = Array(allPosts.dropFirst(currentCount).prefix(batchSize))

        if nextBatch.isEmpty {
            hasMorePosts = false
            print("🔄 Reached the end of following feed")
        } else {
            // 追加分の投稿者も事前取得
            let authorIds = Array(Set(nextBatch.map { $0.userId }))
            _ = try? await FirestoreUserManager.shared.getUsers(userIds: authorIds)

            posts.append(contentsOf: nextBatch)
            hasMorePosts = posts.count < allPosts.count
            print("✅ Loaded \(nextBatch.count) more posts (total: \(posts.count))")
        }

        isLoadingMore = false
    }

    func refreshPosts() async {
        posts = []
        allPosts = []
        hasMorePosts = true
        await loadInitialPosts()
    }
}
