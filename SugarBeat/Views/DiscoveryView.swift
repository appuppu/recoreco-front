import SwiftUI
import FirebaseAuth

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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
            .navigationTitle("すべて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            if viewModel.posts.isEmpty {
                await viewModel.loadInitialPosts()
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class DiscoveryViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var hasMorePosts = true

    private var allPosts: [Post] = []  // Cache all posts for random selection
    private let batchSize = 20

    func loadInitialPosts() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            // Get all posts from Firestore
            let (fetchedPosts, _) = try await FirestorePostManager.shared.getDiscoveryFeed(limit: 100)

            // Filter out posts from blocked users
            let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []
            allPosts = fetchedPosts.filter { !blockedUserIds.contains($0.userId) }

            // Shuffle for random order
            allPosts.shuffle()

            // Load first batch
            posts = Array(allPosts.prefix(batchSize))
            hasMorePosts = allPosts.count > batchSize

            print("✅ Loaded \(posts.count) posts out of \(allPosts.count) total (shuffled)")
        } catch {
            print("❌ Failed to load discovery feed: \(error)")
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
            print("🔄 Looped back to beginning of feed")
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
