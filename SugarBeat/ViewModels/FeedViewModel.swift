import Foundation
import Combine
import SwiftUI

struct UserPosts: Identifiable {
    let id: Int64 // user ID
    let user: User
    var posts: [Post]
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var allUserPosts: [UserPosts] = [] // All users including self, sorted by latest post
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasUnreadDiscoveryPosts = false
    @Published var usersWithUnreadPosts: Set<Int64> = [] // Track users with new posts

    private var latestPostDate: Date?
    private var latestDiscoveryPostDate: Date?
    private var pollingTask: Task<Void, Never>?

    func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let currentUserId = APIClient.shared.currentUserId else {
                errorMessage = "ユーザーIDが取得できません"
                isLoading = false
                return
            }

            // Load discovery feed (limit to 20 posts for performance)
            let discoveryPosts = try await APIClient.shared.getDiscoveryFeed(page: 0, size: 20)
            print("📥 Loaded \(discoveryPosts.count) posts from discovery feed")

            // Load current user's posts (limit to 20 posts for performance)
            let currentUserPostsList = try await APIClient.shared.getUserPosts(userId: currentUserId, page: 0, size: 20)
            print("📥 Loaded \(currentUserPostsList.count) posts for current user \(currentUserId)")

            // Get mutual follows feed
            let mutualFollowsPosts = try await APIClient.shared.getMutualFollowsFeed()
            print("📥 Loaded \(mutualFollowsPosts.count) posts from mutual follows")

            // Combine current user posts and mutual follows posts
            let allPosts = currentUserPostsList + mutualFollowsPosts

            // Group posts by user
            let grouped = Dictionary(grouping: allPosts) { $0.user.id }

            // Create UserPosts for each user and sort by most recent post
            allUserPosts = grouped.map { userId, userPostsList in
                UserPosts(
                    id: userId,
                    user: userPostsList.first!.user,
                    posts: userPostsList.sorted { $0.createdAt > $1.createdAt }
                )
            }.sorted {
                // Sort by latest post timestamp
                $0.posts.first?.createdAt ?? Date.distantPast >
                $1.posts.first?.createdAt ?? Date.distantPast
            }

            // Update latest post date for polling (BEFORE moving current user to front)
            latestPostDate = allUserPosts.first?.posts.first?.createdAt

            // Move current user to the front (always first)
            if let currentUserIndex = allUserPosts.firstIndex(where: { $0.id == currentUserId }) {
                let currentUser = allUserPosts.remove(at: currentUserIndex)
                allUserPosts.insert(currentUser, at: 0)
            }

            // Add discovery feed at the beginning (leftmost) with special ID -1
            // Always add discovery tab even if there are no posts
            let discoveryUser = User(
                id: -1,
                username: "discovery",
                email: nil,
                displayName: "音楽の発見",
                profileImageUrl: nil,
                bio: nil,
                isPublic: nil,
                createdAt: nil,
                isFollowing: nil,
                isFollower: nil,
                isMutual: nil,
                followingCount: nil,
                followerCount: nil
            )
            let discoveryUserPosts = UserPosts(
                id: -1,
                user: discoveryUser,
                posts: discoveryPosts.sorted { $0.createdAt > $1.createdAt }
            )
            allUserPosts.insert(discoveryUserPosts, at: 0)

            // Update latest discovery post date
            latestDiscoveryPostDate = discoveryUserPosts.posts.first?.createdAt

            // Update LikeStateManager and CommentStateManager with server data
            for userPosts in allUserPosts {
                for post in userPosts.posts {
                    LikeStateManager.shared.updateFromServer(
                        postId: post.id,
                        isLiked: post.isLiked ?? false,
                        count: post.likeCount ?? 0
                    )
                    CommentStateManager.shared.updateFromServer(
                        postId: post.id,
                        count: post.commentCount ?? 0
                    )
                }
            }

            print("📊 Total users in feed: \(allUserPosts.count)")

        } catch {
            // Ignore cancellation errors (happens when quickly switching between users)
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("⚠️ Feed load cancelled (normal when switching users quickly)")
                return
            }

            errorMessage = "フィードの読み込みに失敗しました: \(error.localizedDescription)"
            print("❌ Failed to load feed: \(error)")
        }

        isLoading = false
    }

    func refreshFeed() async {
        await loadFeed()
    }

    // Start polling for new posts every 30 seconds
    func startPolling() {
        stopPolling() // Stop any existing polling

        pollingTask = Task {
            while !Task.isCancelled {
                // Wait 30 seconds before checking
                try? await Task.sleep(nanoseconds: 30_000_000_000)

                if Task.isCancelled { break }

                await checkForNewPosts()
            }
        }

        print("🔄 Started polling for new posts (30s interval)")
    }

    // Stop polling
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        print("⏸️ Stopped polling for new posts")
    }

    // Check for new posts silently (without showing loading indicator)
    private func checkForNewPosts() async {
        guard let latestDate = latestPostDate else {
            print("🔄 No latest post date, skipping poll")
            return
        }

        do {
            guard let currentUserId = APIClient.shared.currentUserId else {
                return
            }

            // Load discovery feed (only check recent 10 posts for efficiency during polling)
            let discoveryPosts = try await APIClient.shared.getDiscoveryFeed(page: 0, size: 10)

            // Load current user's posts (only check recent 10 posts for efficiency during polling)
            let currentUserPostsList = try await APIClient.shared.getUserPosts(userId: currentUserId, page: 0, size: 10)

            // Get mutual follows feed
            let mutualFollowsPosts = try await APIClient.shared.getMutualFollowsFeed()

            // Combine posts
            let allPosts = currentUserPostsList + mutualFollowsPosts

            // Check if there are any new posts in follows or discovery
            let hasNewFollowPosts = allPosts.contains { $0.createdAt > latestDate }

            let hasNewDiscoveryPosts: Bool
            if let latestDiscoveryDate = latestDiscoveryPostDate {
                hasNewDiscoveryPosts = discoveryPosts.contains { $0.createdAt > latestDiscoveryDate }
            } else {
                hasNewDiscoveryPosts = !discoveryPosts.isEmpty
            }

            if hasNewFollowPosts || hasNewDiscoveryPosts {
                print("🆕 New posts detected (follow: \(hasNewFollowPosts), discovery: \(hasNewDiscoveryPosts)), refreshing feed silently")

                // Set unread flag for discovery if new posts detected
                if hasNewDiscoveryPosts {
                    self.hasUnreadDiscoveryPosts = true
                }

                // Track which users have new posts
                if hasNewFollowPosts {
                    var usersWithNewPosts: Set<Int64> = []
                    for post in allPosts {
                        if post.createdAt > latestDate {
                            usersWithNewPosts.insert(post.user.id)
                        }
                    }
                    self.usersWithUnreadPosts.formUnion(usersWithNewPosts)
                }

                // Group posts by user
                let grouped = Dictionary(grouping: allPosts) { $0.user.id }

                // Create UserPosts for each user and sort by most recent post
                allUserPosts = grouped.map { userId, userPostsList in
                    UserPosts(
                        id: userId,
                        user: userPostsList.first!.user,
                        posts: userPostsList.sorted { $0.createdAt > $1.createdAt }
                    )
                }.sorted {
                    $0.posts.first?.createdAt ?? Date.distantPast >
                    $1.posts.first?.createdAt ?? Date.distantPast
                }

                // Update latest post date (BEFORE moving current user to front)
                latestPostDate = allUserPosts.first?.posts.first?.createdAt

                // Move current user to the front (always first)
                if let currentUserIndex = allUserPosts.firstIndex(where: { $0.id == currentUserId }) {
                    let currentUser = allUserPosts.remove(at: currentUserIndex)
                    allUserPosts.insert(currentUser, at: 0)
                }

                // Add discovery feed at the beginning (leftmost) with special ID -1
                // Always add discovery tab even if there are no posts
                let discoveryUser = User(
                    id: -1,
                    username: "discovery",
                    email: nil,
                    displayName: "音楽の発見",
                    profileImageUrl: nil,
                    bio: nil,
                    isPublic: nil,
                    createdAt: nil,
                    isFollowing: nil,
                    isFollower: nil,
                    isMutual: nil,
                    followingCount: nil,
                    followerCount: nil
                )
                let discoveryUserPosts = UserPosts(
                    id: -1,
                    user: discoveryUser,
                    posts: discoveryPosts.sorted { $0.createdAt > $1.createdAt }
                )
                allUserPosts.insert(discoveryUserPosts, at: 0)

                // Update latest discovery post date
                latestDiscoveryPostDate = discoveryUserPosts.posts.first?.createdAt

                // Update LikeStateManager and CommentStateManager with server data
                for userPosts in allUserPosts {
                    for post in userPosts.posts {
                        LikeStateManager.shared.updateFromServer(
                            postId: post.id,
                            isLiked: post.isLiked ?? false,
                            count: post.likeCount ?? 0
                        )
                        CommentStateManager.shared.updateFromServer(
                            postId: post.id,
                            count: post.commentCount ?? 0
                        )
                    }
                }

                print("✅ Feed refreshed with new posts")
            } else {
                print("🔄 No new posts")
            }

        } catch {
            // Silently ignore errors during polling
            if let urlError = error as? URLError, urlError.code == .cancelled {
                // Normal cancellation, ignore
                return
            }
            print("⚠️ Polling error (ignored): \(error.localizedDescription)")
        }
    }
}
