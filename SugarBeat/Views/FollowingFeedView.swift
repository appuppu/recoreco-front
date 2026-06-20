import SwiftUI
import FirebaseAuth

/// フォロー中タブ - フォローしているユーザーの投稿を縦スワイプ表示
struct FollowingFeedView: View {
    @StateObject private var viewModel = FollowingFeedViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingLoginSheet = false

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
                    VerticalSwipeFeedView(
                        posts: viewModel.posts,
                        isLoading: viewModel.isLoading,
                        onLoadMore: {
                            await viewModel.loadMorePosts()
                        },
                        onRefresh: {
                            await viewModel.refreshPosts()
                        }
                    )
                }
            }
            .navigationTitle("フォロー中")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

            // Get list of followed user IDs
            let followedUserIds = try await FirestoreFollowManager.shared.getFollowingIds(userId: currentUserId)

            guard !followedUserIds.isEmpty else {
                allPosts = []
                posts = []
                isLoading = false
                return
            }

            // Get posts from followed users
            let (fetchedPosts, _) = try await FirestorePostManager.shared.getFollowingFeed(
                userIds: followedUserIds,
                limit: 100
            )

            // Filter out blocked users
            let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []
            allPosts = fetchedPosts.filter { !blockedUserIds.contains($0.userId) }

            // Shuffle for random order
            allPosts.shuffle()

            // Load first batch
            posts = Array(allPosts.prefix(batchSize))
            hasMorePosts = allPosts.count > batchSize

            print("✅ Loaded \(posts.count) posts from \(followedUserIds.count) followed users (shuffled)")
        } catch {
            print("❌ Failed to load following feed: \(error)")
        }

        isLoading = false
    }

    func loadMorePosts() async {
        guard hasMorePosts, !isLoading else { return }

        let currentCount = posts.count
        let nextBatch = Array(allPosts.dropFirst(currentCount).prefix(batchSize))

        if nextBatch.isEmpty {
            // Reached the end, loop back to beginning
            posts = Array(allPosts.prefix(batchSize))
            print("🔄 Looped back to beginning of following feed")
        } else {
            posts.append(contentsOf: nextBatch)
            hasMorePosts = posts.count < allPosts.count
            print("✅ Loaded \(nextBatch.count) more posts (total: \(posts.count))")
        }
    }

    func refreshPosts() async {
        posts = []
        allPosts = []
        hasMorePosts = true
        await loadInitialPosts()
    }
}
