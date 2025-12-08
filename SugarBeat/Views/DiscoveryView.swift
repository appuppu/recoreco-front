import SwiftUI
import Foundation

// MARK: - Notification Name Extension
extension Foundation.Notification.Name {
    static let postCreated = Foundation.Notification.Name("postCreated")
    static let postDeleted = Foundation.Notification.Name("postDeleted")
    static let userBlocked = Foundation.Notification.Name("userBlocked")
}

/// 発見タブ - Discovery Feedの投稿をグリッド表示
struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false


    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.posts.isEmpty {
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
                    Text("投稿がありません")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
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
            // 初回のみ読み込み（キャッシュがない場合）
            if viewModel.posts.isEmpty {
                await viewModel.loadPosts()
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
class DiscoveryViewModel: ObservableObject {
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
                print("🚫 Discovery received block notification for userId: \(userId)")
                let beforeCount = self?.posts.count ?? 0
                self?.posts.removeAll { $0.user.id == userId }
                let afterCount = self?.posts.count ?? 0
                print("🚫 Discovery posts removed: \(beforeCount - afterCount) posts")
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
                print("📦 Discovery: Using cache (elapsed: \(Int(elapsed))s)")
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
            // Discovery feedから投稿を取得（新しい順）
            let fetchedPosts = try await APIClient.shared.getDiscoveryFeed(page: 0, size: 50)
            // 新しい順にソート（createdAtが新しいものが先頭）
            posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
            lastFetchTime = Date()
            print("📥 Discovery: Loaded \(posts.count) posts")
        } catch let error as NSError {
            // キャンセルエラー(-999)は無視
            if error.code == NSURLErrorCancelled {
                print("⚠️ Discovery: Request cancelled")
            } else {
                errorMessage = "読み込みに失敗しました"
                print("❌ Discovery: Failed to load posts: \(error)")
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
