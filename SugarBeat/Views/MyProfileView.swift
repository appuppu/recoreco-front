import SwiftUI

/// プロフィールタブ - 自分の投稿一覧を表示（発見タブと同じデザイン）
struct MyProfileView: View {
    @Binding var pendingPlayPostId: Int64?
    @StateObject private var viewModel = MyProfileViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false

    init(pendingPlayPostId: Binding<Int64?> = .constant(nil)) {
        self._pendingPlayPostId = pendingPlayPostId
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !authManager.isAuthenticated {
                // 未ログイン状態
                VStack(spacing: 20) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.4))
                    Text("ログインして\n自分の投稿を見る")
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
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.4))
                    Text("まだ投稿がありません")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("左下の+ボタンから\n音楽を投稿してみましょう")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            } else {
                PostGridView(
                    posts: viewModel.posts,
                    showingLoginPrompt: $showingLoginPrompt,
                    showUserInfo: true, // 自分の投稿でもユーザー情報を表示
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
        .onChange(of: pendingPlayPostId) { postId in
            if let postId = postId {
                playPendingPost(postId: postId)
            }
        }
        .onChange(of: viewModel.posts.count) { _ in
            // Posts loaded, check if we have a pending post to play
            if let postId = pendingPlayPostId {
                playPendingPost(postId: postId)
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

    private func playPendingPost(postId: Int64) {
        guard let post = viewModel.posts.first(where: { $0.id == postId }) else {
            // Post not found yet, wait for posts to load
            return
        }

        // Clear the pending post ID
        pendingPlayPostId = nil

        // Start playback
        Task {
            if let previewUrl = post.previewUrl {
                do {
                    try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime)
                    playbackState.startPlayback(for: post.id, userId: post.user.id, post: post, user: post.user)
                    print("🎵 Playing post from notification: \(post.id)")
                } catch {
                    print("❌ Failed to play post: \(error)")
                }
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class MyProfileViewModel: ObservableObject {
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
    }

    func loadPosts(forceRefresh: Bool = false) async {
        guard let currentUserId = AuthManager().currentUser?.userId else {
            errorMessage = "ユーザー情報を取得できません"
            return
        }

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
                print("📦 My Profile: Using cache (elapsed: \(Int(elapsed))s)")
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
            // 自分の投稿を取得（新しい順）
            let fetchedPosts = try await APIClient.shared.getUserPosts(userId: currentUserId, page: 0, size: 50, sort: "desc")
            posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
            lastFetchTime = Date()
            print("📥 My Profile: Loaded \(posts.count) posts")
        } catch let error as NSError {
            // キャンセルエラー(-999)は無視
            if error.code == NSURLErrorCancelled {
                print("⚠️ My Profile: Request cancelled")
            } else {
                errorMessage = "読み込みに失敗しました"
                print("❌ My Profile: Failed to load posts: \(error)")
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
