import SwiftUI
import FirebaseFirestore

/// アーティスト名で投稿を検索した結果を表示する画面
///
/// - 「"アーティスト名"の検索結果」見出し
/// - プロフィールと同じ PostGridView でグリッド表示
/// - 30件ずつページング
struct ArtistPostsView: View {
    let artistName: String

    @StateObject private var viewModel = ArtistPostsViewModel()
    @State private var showingLoginPrompt = false
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 見出し
                HStack {
                    Text("「\(artistName)」の投稿一覧")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black)

                if viewModel.isLoading && viewModel.posts.isEmpty {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if viewModel.posts.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.4))
                        Text("投稿が見つかりませんでした")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                } else {
                    PostGridView(
                        posts: viewModel.posts,
                        showingLoginPrompt: $showingLoginPrompt,
                        showUserInfo: true,
                        isLoading: viewModel.isLoading,
                        isLoadingMore: viewModel.isLoadingMore,
                        onRefresh: {
                            await viewModel.refresh(artistName: artistName)
                        },
                        onLoadMore: {
                            await viewModel.loadMore(artistName: artistName)
                        },
                        topPadding: 0
                    )
                    .environmentObject(authManager)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showingLoginPrompt) {
            LoginView()
        }
        .task {
            if viewModel.posts.isEmpty {
                await viewModel.loadInitial(artistName: artistName)
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class ArtistPostsViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMorePosts = true

    private let pageSize = 30
    private var lastDocument: DocumentSnapshot?

    func loadInitial(artistName: String) async {
        guard !isLoading else { return }
        isLoading = true
        lastDocument = nil
        hasMorePosts = true

        do {
            let (fetched, lastDoc) = try await FirestorePostManager.shared.getPostsByArtist(
                artistName: artistName, limit: pageSize
            )
            posts = fetched
            lastDocument = lastDoc
            hasMorePosts = fetched.count >= pageSize

            // 投稿者をまとめて事前取得してキャッシュを温める
            let authorIds = Array(Set(posts.map { $0.userId }))
            _ = try? await FirestoreUserManager.shared.getUsers(userIds: authorIds)
        } catch {
            print("❌ Failed to load artist posts: \(error)")
        }

        isLoading = false
    }

    func loadMore(artistName: String) async {
        guard hasMorePosts, !isLoadingMore, !isLoading, let lastDoc = lastDocument else { return }
        isLoadingMore = true

        do {
            let (fetched, newLastDoc) = try await FirestorePostManager.shared.getPostsByArtist(
                artistName: artistName, limit: pageSize, lastDocument: lastDoc
            )
            posts.append(contentsOf: fetched)
            lastDocument = newLastDoc
            hasMorePosts = fetched.count >= pageSize

            let authorIds = Array(Set(fetched.map { $0.userId }))
            _ = try? await FirestoreUserManager.shared.getUsers(userIds: authorIds)
        } catch {
            print("❌ Failed to load more artist posts: \(error)")
        }

        isLoadingMore = false
    }

    func refresh(artistName: String) async {
        posts = []
        lastDocument = nil
        hasMorePosts = true
        await loadInitial(artistName: artistName)
    }
}
