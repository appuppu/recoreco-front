import Foundation
import Combine
import SwiftUI
import FirebaseAuth

struct UserPosts: Identifiable {
    let id: String // user ID
    let user: User
    var posts: [Post]
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var allUserPosts: [UserPosts] = [] // All users including self, sorted by latest post
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var usersWithUnreadPosts: Set<String> = [] // Track users with new posts

    private var latestPostDate: Date?
    private var pollingTask: Task<Void, Never>?

    init() {
        // ユーザーブロック通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.userBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userId = notification.userInfo?["blockedUserId"] as? String {
                print("🚫 FeedViewModel received block notification for userId: \(userId)")
                // Remove the blocked user from allUserPosts
                self?.allUserPosts.removeAll { $0.id == userId }
                print("🚫 FeedViewModel: Removed blocked user's posts")
            }
        }

        // 投稿削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let postId = notification.userInfo?["postId"] as? String {
                // Remove the deleted post from all user posts
                for i in 0..<(self?.allUserPosts.count ?? 0) {
                    self?.allUserPosts[i].posts.removeAll { $0.id == postId }
                }
                // Remove users with no posts
                self?.allUserPosts.removeAll { $0.posts.isEmpty }
            }
        }
    }

    func loadFeed() async {
        isLoading = true
        errorMessage = nil

        do {
            // Check if user is authenticated
            if let currentUserId = Auth.auth().currentUser?.uid {
                // Authenticated user: Load own posts + following posts
                // Load current user's posts (limit to 50 posts for performance)
                let (currentUserPostsList, _) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 50)
                print("📥 Loaded \(currentUserPostsList.count) posts for current user \(currentUserId)")

                // Get following user IDs
                let followingIds = try await FirestoreFollowManager.shared.getFollowingIds(userId: currentUserId)

                // Get following users' posts
                let (followingPosts, _) = followingIds.isEmpty ? ([], nil) : try await FirestorePostManager.shared.getFollowingFeed(userIds: followingIds, limit: 100)
                print("📥 Loaded \(followingPosts.count) posts from following users")

                // Combine current user posts and following posts
                let allPosts = currentUserPostsList + followingPosts

                // Group posts by user
                let grouped = Dictionary(grouping: allPosts) { $0.userId }

                // Batch fetch user info to avoid N+1 queries
                let userIds = Array(grouped.keys)
                let users = try await FirestoreUserManager.shared.getUsers(userIds: userIds)
                let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id ?? "", $0) })

                // Create UserPosts for each user and sort by most recent post
                var userPostsArray: [UserPosts] = []
                for (userId, userPostsList) in grouped {
                    guard let user = userMap[userId] else { continue }
                    let sortedPosts = userPostsList.sorted { $0.createdAt > $1.createdAt }
                    userPostsArray.append(UserPosts(
                        id: userId,
                        user: user,
                        posts: sortedPosts
                    ))
                }

                // Sort by latest post timestamp
                allUserPosts = userPostsArray.sorted { a, b in
                    let aDate = a.posts.first?.createdAt ?? Date.distantPast
                    let bDate = b.posts.first?.createdAt ?? Date.distantPast
                    return aDate > bDate
                }

                // Update latest post date for polling
                latestPostDate = allUserPosts.first?.posts.first?.createdAt

                print("📊 Total users in feed: \(allUserPosts.count)")
            } else {
                // Unauthenticated user: Show empty feed
                allUserPosts = []
            }

            // Update LikeStateManager and CommentStateManager with Firestore data
            for userPosts in allUserPosts {
                for post in userPosts.posts {
                    if let postId = post.id {
                        LikeStateManager.shared.updateFromServer(
                            postId: postId,
                            isLiked: post.isLiked ?? false,
                            count: post.likeCount ?? 0
                        )
                        CommentStateManager.shared.updateFromServer(
                            postId: postId,
                            count: post.commentCount ?? 0
                        )
                    }
                }
            }

            print("📊 Total users in feed: \(allUserPosts.count)")

        } catch {
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
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                return
            }

            // Load current user's posts (only check recent 10 posts for efficiency during polling)
            let (currentUserPostsList, _) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 10)

            // Get following user IDs
            let followingIds = try await FirestoreFollowManager.shared.getFollowingIds(userId: currentUserId)

            // Get following users' posts
            let (followingPosts, _) = followingIds.isEmpty ? ([], nil) : try await FirestorePostManager.shared.getFollowingFeed(userIds: followingIds, limit: 50)

            // Combine posts
            let allPosts = currentUserPostsList + followingPosts

            // Check if there are any new posts
            let hasNewPosts = allPosts.contains { $0.createdAt > latestDate }

            if hasNewPosts {
                print("🆕 New posts detected, refreshing feed silently")

                // Track which users have new posts
                var usersWithNewPosts: Set<String> = []
                for post in allPosts {
                    if post.createdAt > latestDate {
                        usersWithNewPosts.insert(post.userId)
                    }
                }
                self.usersWithUnreadPosts.formUnion(usersWithNewPosts)

                // Group posts by user
                let grouped = Dictionary(grouping: allPosts) { $0.userId }

                // Batch fetch user info to avoid N+1 queries
                let userIds = Array(grouped.keys)
                let users = try await FirestoreUserManager.shared.getUsers(userIds: userIds)
                let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id ?? "", $0) })

                // Create UserPosts for each user and sort by most recent post
                var userPostsArray: [UserPosts] = []
                for (userId, userPostsList) in grouped {
                    guard let user = userMap[userId] else { continue }
                    let sortedPosts = userPostsList.sorted { $0.createdAt > $1.createdAt }
                    userPostsArray.append(UserPosts(
                        id: userId,
                        user: user,
                        posts: sortedPosts
                    ))
                }

                // Sort by latest post timestamp
                allUserPosts = userPostsArray.sorted { a, b in
                    let aDate = a.posts.first?.createdAt ?? Date.distantPast
                    let bDate = b.posts.first?.createdAt ?? Date.distantPast
                    return aDate > bDate
                }

                // Update latest post date
                latestPostDate = allUserPosts.first?.posts.first?.createdAt

                // Update LikeStateManager and CommentStateManager with Firestore data
                for userPosts in allUserPosts {
                    for post in userPosts.posts {
                        if let postId = post.id {
                            LikeStateManager.shared.updateFromServer(
                                postId: postId,
                                isLiked: post.isLiked ?? false,
                                count: post.likeCount ?? 0
                            )
                            CommentStateManager.shared.updateFromServer(
                                postId: postId,
                                count: post.commentCount ?? 0
                            )
                        }
                    }
                }

                print("✅ Feed refreshed with new posts")
            } else {
                print("🔄 No new posts")
            }

        } catch {
            // Silently ignore errors during polling
            print("⚠️ Polling error (ignored): \(error.localizedDescription)")
        }
    }
}
