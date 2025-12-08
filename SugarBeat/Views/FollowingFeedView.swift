import SwiftUI

/// フォロー中タブ - フォロー中ユーザーの投稿をグリッド表示（自分の投稿は除外）
struct FollowingFeedView: View {
    @StateObject private var viewModel = FollowingFeedViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !authManager.isAuthenticated {
                // 未ログイン状態
                VStack(spacing: 20) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.4))
                    Text("ログインしてフォロー中の\nユーザーの投稿を見る")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("ログイン") {
                        showingLoginSheet = true
                    }
                    .foregroundColor(.purple)
                    .font(.headline)
                }
            } else if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
                    .tint(.white)
            } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red.opacity(0.7))
                    Text(errorMessage)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("再読み込み") {
                        Task {
                            await viewModel.loadPosts()
                        }
                    }
                    .foregroundColor(.purple)
                }
                .padding()
            } else if viewModel.posts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.4))
                    Text("フォロー中のユーザーの\n投稿がありません")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            } else {
                PostGridView(
                    posts: viewModel.posts,
                    showingLoginPrompt: $showingLoginPrompt,
                    showUserInfo: true,
                    isLoading: viewModel.isLoading,
                    onRefresh: {
                        await viewModel.loadPosts(forceRefresh: true)
                    }
                )
            }
        }
        .task {
            if viewModel.posts.isEmpty && authManager.isAuthenticated {
                await viewModel.loadPosts()
            }
        }
        .onChange(of: authManager.isAuthenticated) { isAuthenticated in
            if isAuthenticated && viewModel.posts.isEmpty {
                Task {
                    await viewModel.loadPosts()
                }
            }
        }
        .alert("ログインが必要です", isPresented: $showingLoginPrompt) {
            Button("はい") {
                showingLoginSheet = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この機能を使用するにはログインが必要です")
        }
        .sheet(isPresented: $showingLoginSheet) {
            LoginView()
        }
    }
}

// MARK: - ViewModel
@MainActor
class FollowingFeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var lastFetchTime: Date?
    private let cacheValidDuration: TimeInterval = 30 // 30秒キャッシュ

    init() {
        // 投稿完了通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadPosts(forceRefresh: true)
            }
        }

        // 投稿削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let postId = notification.userInfo?["postId"] as? Int64 {
                self?.posts.removeAll { $0.id == postId }
            }
        }

        // ユーザーブロック通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.userBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userId = notification.userInfo?["userId"] as? Int64 {
                print("🚫 FollowingFeed received block notification for userId: \(userId)")
                let beforeCount = self?.posts.count ?? 0
                self?.posts.removeAll { $0.user.id == userId }
                let afterCount = self?.posts.count ?? 0
                print("🚫 FollowingFeed posts removed: \(beforeCount - afterCount) posts")
            }
        }
    }

    func loadPosts(forceRefresh: Bool = false) async {
        let startTime = Date()
        let minimumLoadingTime: TimeInterval = 1.5

        // プルリフレッシュの場合はローディング表示
        if forceRefresh {
            isLoading = true
        }

        // キャッシュが有効な場合はスキップ（30秒以内）
        if let lastFetch = lastFetchTime {
            let elapsed = Date().timeIntervalSince(lastFetch)
            if elapsed < cacheValidDuration && !posts.isEmpty {
                print("📦 Following Feed: Using cache (elapsed: \(Int(elapsed))s)")
                // キャッシュ使用時もローディングアニメーションを表示
                if forceRefresh {
                    try? await Task.sleep(nanoseconds: UInt64(minimumLoadingTime * 1_000_000_000))
                    isLoading = false
                }
                return
            }
        }

        errorMessage = nil

        do {
            // フォロー中のユーザーの投稿を取得
            let fetchedPosts = try await APIClient.shared.getMutualFollowsFeed()

            // 自分の投稿を除外し、新しい順にソート
            let currentUserId = AuthManager().currentUser?.userId
            posts = fetchedPosts
                .filter { $0.user.id != currentUserId }
                .sorted { $0.createdAt > $1.createdAt }

            lastFetchTime = Date()
            print("📥 Following Feed: Loaded \(posts.count) posts (excluded own posts)")
        } catch let error as NSError {
            // キャンセルエラー(-999)は無視
            if error.code == NSURLErrorCancelled {
                print("⚠️ Following Feed: Request cancelled")
            } else {
                errorMessage = "読み込みに失敗しました"
                print("❌ Following Feed: Failed to load posts: \(error)")
            }
        }

        // プルリフレッシュの場合は最低1.5秒間ローディングを表示
        if forceRefresh {
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime < minimumLoadingTime {
                try? await Task.sleep(nanoseconds: UInt64((minimumLoadingTime - elapsedTime) * 1_000_000_000))
            }
            isLoading = false
        }
    }
}
