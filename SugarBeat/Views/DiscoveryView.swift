import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DiscoveryView: View {
    var reloadTrigger: Int = 0
    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject var authManager: AuthManager
    @State private var showingLoginPrompt = false
    @State private var scrollToTopTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showingLoginPrompt) {
            LoginView()
        }
        .task {
            if viewModel.posts.isEmpty {
                await viewModel.loadInitialPosts()
            }
        }
        .onChange(of: reloadTrigger) { _ in
            // タブ再タップ: 一番上へスクロールするだけ（更新はしない）
            scrollToTopTrigger += 1
        }
    }
}

// MARK: - ViewModel
@MainActor
class DiscoveryViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMorePosts = true

    // ブロック単位ランダム表示:
    // createdAt降順で blockSize 件ずつ取得し、各ブロック内をシャッフルして追加する。
    // これにより「新しい投稿群をランダム → 尽きたら古い投稿群をランダム」という流れになる。
    private let blockSize = 30
    private var lastDocument: DocumentSnapshot? = nil
    private var blockedUserIds: [String] = []

    func loadInitialPosts() async {
        guard !isLoading else { return }
        isLoading = true

        // ブロックユーザーを取得（フィルタ用にキャッシュ）
        blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []

        posts = []
        lastDocument = nil
        hasMorePosts = true

        await fetchNextBlock()

        isLoading = false
    }

    func loadMorePosts() async {
        guard hasMorePosts, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        await fetchNextBlock()
        isLoadingMore = false
    }

    /// 次のブロック（createdAt降順で blockSize 件）を取得し、シャッフルして posts に追加する
    private func fetchNextBlock() async {
        do {
            let (fetchedPosts, lastDoc) = try await FirestorePostManager.shared.getDiscoveryFeed(
                limit: blockSize,
                lastDocument: lastDocument
            )

            // これ以上投稿が無ければ終了
            guard !fetchedPosts.isEmpty else {
                hasMorePosts = false
                print("🔄 Reached the end of discovery feed")
                return
            }

            lastDocument = lastDoc
            // blockSize 未満しか返らなければ最後のブロック
            hasMorePosts = fetchedPosts.count >= blockSize

            // ブロックユーザーを除外し、ブロック内でシャッフルして追加
            let block = fetchedPosts
                .filter { !blockedUserIds.contains($0.userId) }
                .shuffled()

            // 投稿者をまとめて事前取得してキャッシュを温める
            // （各カードが個別に getUser を呼ぶ前にキャッシュを満たし、
            //   Firestoreへのリクエストを「重複ユーザーをまとめた最小回数」に抑える）
            let authorIds = Array(Set(block.map { $0.userId }))
            _ = try? await FirestoreUserManager.shared.getUsers(userIds: authorIds)

            posts.append(contentsOf: block)

            print("✅ Loaded block of \(block.count) posts (total: \(posts.count), hasMore: \(hasMorePosts))")
        } catch {
            print("❌ Failed to load discovery feed block: \(error)")
        }
    }

    func refreshPosts() async {
        posts = []
        lastDocument = nil
        hasMorePosts = true
        await loadInitialPosts()
    }
}
