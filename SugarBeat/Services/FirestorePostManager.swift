import Foundation
import FirebaseFirestore
import FirebaseAuth

enum FirestorePostError: Error {
    case postNotFound
    case invalidData
    case createFailed(Error)
    case updateFailed(Error)
    case deleteFailed(Error)
    case fetchFailed(Error)
    case notAuthenticated
    case unauthorized

    var localizedDescription: String {
        switch self {
        case .postNotFound:
            return "投稿が見つかりません"
        case .invalidData:
            return "無効なデータです"
        case .createFailed(let error):
            return "作成に失敗しました: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "更新に失敗しました: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "削除に失敗しました: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "取得に失敗しました: \(error.localizedDescription)"
        case .notAuthenticated:
            return "認証が必要です"
        case .unauthorized:
            return "権限がありません"
        }
    }
}

class FirestorePostManager {
    static let shared = FirestorePostManager()
    private let db = Firestore.firestore()
    private let postsCollection = "posts"

    private init() {}

    // MARK: - Create Post

    func createPost(_ post: Post) async throws -> String {
        do {
            let docRef = try db.collection(postsCollection).addDocument(from: post)
            print("✅ Post created: \(docRef.documentID)")

            // Increment user's post count
            try await FirestoreUserManager.shared.incrementPostCount(userId: post.userId)

            return docRef.documentID
        } catch {
            throw FirestorePostError.createFailed(error)
        }
    }

    // MARK: - Helper Methods
    // User info is now fetched dynamically by views, not denormalized into posts

    // MARK: - Get Post

    func getPost(postId: String) async throws -> Post {
        do {
            let document = try await db.collection(postsCollection).document(postId).getDocument()

            guard document.exists else {
                throw FirestorePostError.postNotFound
            }

            var post = try document.data(as: Post.self)

            // Check if current user liked this post and get counts
            if let currentUserId = Auth.auth().currentUser?.uid {
                post.isLiked = try await FirestoreLikeManager.shared.isPostLiked(postId: postId, userId: currentUserId)
            }

            // Get like count and comment count
            post.likeCount = await getLikeCount(postId: postId)
            post.commentCount = await getCommentCount(postId: postId)

            return post
        } catch {
            throw FirestorePostError.postNotFound
        }
    }

    // MARK: - Update Post

    func updatePost(postId: String, comment: String?) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        do {
            // Verify ownership
            let post = try await getPost(postId: postId)
            guard post.userId == currentUserId else {
                throw FirestorePostError.unauthorized
            }

            try await db.collection(postsCollection).document(postId).updateData([
                "comment": comment ?? "",
                "updatedAt": FieldValue.serverTimestamp()
            ])
            print("✅ Post updated: \(postId)")
        } catch {
            throw FirestorePostError.updateFailed(error)
        }
    }

    // MARK: - Delete Post

    func deletePost(postId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        do {
            // Verify ownership
            let post = try await getPost(postId: postId)
            guard post.userId == currentUserId else {
                throw FirestorePostError.unauthorized
            }

            // Delete post
            try await db.collection(postsCollection).document(postId).delete()

            // Decrement user's post count
            try await FirestoreUserManager.shared.decrementPostCount(userId: currentUserId)

            print("✅ Post deleted: \(postId)")
        } catch {
            throw FirestorePostError.deleteFailed(error)
        }
    }

    // MARK: - Get Posts

    // MARK: - Batch Check Likes (OPTIMIZED)

    private func batchCheckLikes(posts: [Post], userId: String) async throws -> [Post] {
        var updatedPosts = posts

        // Batch check likes and counts to reduce queries
        let postIds = posts.compactMap { $0.id }

        guard !postIds.isEmpty else { return updatedPosts }

        // Use Task group for parallel execution
        await withTaskGroup(of: (Int, Bool, Int, Int).self) { group in
            for (index, postId) in postIds.enumerated() {
                group.addTask {
                    let isLiked = (try? await FirestoreLikeManager.shared.isPostLiked(postId: postId, userId: userId)) ?? false

                    // Get like count
                    let likeCount = await self.getLikeCount(postId: postId)

                    // Get comment count
                    let commentCount = await self.getCommentCount(postId: postId)

                    return (index, isLiked, likeCount, commentCount)
                }
            }

            for await (index, isLiked, likeCount, commentCount) in group {
                updatedPosts[index].isLiked = isLiked
                updatedPosts[index].likeCount = likeCount
                updatedPosts[index].commentCount = commentCount
            }
        }

        return updatedPosts
    }

    private func getLikeCount(postId: String) async -> Int {
        do {
            let snapshot = try await db.collection(postsCollection)
                .document(postId)
                .collection("likes")
                .getDocuments()
            return snapshot.documents.count
        } catch {
            return 0
        }
    }

    private func getCommentCount(postId: String) async -> Int {
        do {
            let snapshot = try await db.collection(postsCollection)
                .document(postId)
                .collection("comments")
                .getDocuments()
            return snapshot.documents.count
        } catch {
            return 0
        }
    }

    func getUserPosts(userId: String, limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> ([Post], DocumentSnapshot?) {
        do {
            var query = db.collection(postsCollection)
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            var posts = try snapshot.documents.compactMap { try $0.data(as: Post.self) }

            // Batch check likes (optimized with parallel execution)
            if let currentUserId = Auth.auth().currentUser?.uid {
                posts = try await batchCheckLikes(posts: posts, userId: currentUserId)
            }

            let lastDoc = snapshot.documents.last
            return (posts, lastDoc)
        } catch {
            throw FirestorePostError.fetchFailed(error)
        }
    }

    // MARK: - Get Channel Posts

    func getChannelPosts(channelId: String, limit: Int = 50, forceRefresh: Bool = false) async throws -> [Post] {
        print("📥 [PostManager] getChannelPosts - channelId: \(channelId), forceRefresh: \(forceRefresh)")
        do {
            let query = db.collection(postsCollection)
                .whereField("channelId", isEqualTo: channelId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

            let snapshot = try await query.getDocuments(source: forceRefresh ? .server : .default)
            print("📥 [PostManager] Fetched \(snapshot.documents.count) posts from \(forceRefresh ? "SERVER" : "CACHE")")
            var posts = try snapshot.documents.compactMap { try $0.data(as: Post.self) }

            // Batch check likes (optimized with parallel execution)
            if let currentUserId = Auth.auth().currentUser?.uid {
                posts = try await batchCheckLikes(posts: posts, userId: currentUserId)
            }

            return posts
        } catch {
            throw FirestorePostError.fetchFailed(error)
        }
    }

    // MARK: - Get Discovery Feed

    func getDiscoveryFeed(limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> ([Post], DocumentSnapshot?) {
        do {
            var query = db.collection(postsCollection)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            var posts = try snapshot.documents.compactMap { try $0.data(as: Post.self) }

            // Cache posts
            FirestoreCacheManager.shared.cachePosts(posts)

            // Batch check likes (optimized)
            if let currentUserId = Auth.auth().currentUser?.uid {
                posts = try await batchCheckLikes(posts: posts, userId: currentUserId)
            }

            let lastDoc = snapshot.documents.last
            return (posts, lastDoc)
        } catch {
            throw FirestorePostError.fetchFailed(error)
        }
    }

    // MARK: - Get Following Feed

    func getFollowingFeed(userIds: [String], limit: Int = 20, lastDocument: DocumentSnapshot? = nil) async throws -> ([Post], DocumentSnapshot?) {
        guard !userIds.isEmpty else {
            return ([], nil)
        }

        do {
            // Firestore 'in' query supports up to 10 values
            let chunkedUserIds = userIds.chunked(into: 10)
            var allPosts: [Post] = []

            for chunk in chunkedUserIds {
                var query = db.collection(postsCollection)
                    .whereField("userId", in: chunk)
                    .order(by: "createdAt", descending: true)
                    .limit(to: limit)

                if let lastDocument = lastDocument {
                    query = query.start(afterDocument: lastDocument)
                }

                let snapshot = try await query.getDocuments()
                let posts = try snapshot.documents.compactMap { try $0.data(as: Post.self) }
                allPosts.append(contentsOf: posts)
            }

            // Sort by createdAt descending
            allPosts.sort { $0.createdAt > $1.createdAt }
            allPosts = Array(allPosts.prefix(limit))

            // Check if current user liked these posts
            if let currentUserId = Auth.auth().currentUser?.uid {
                for i in 0..<allPosts.count {
                    allPosts[i].isLiked = try await FirestoreLikeManager.shared.isPostLiked(postId: allPosts[i].id ?? "", userId: currentUserId)
                }
            }

            return (allPosts, nil)
        } catch {
            throw FirestorePostError.fetchFailed(error)
        }
    }

    // MARK: - Counters
    // Like and comment counts are now managed by subcollections, not stored in posts

    // MARK: - Real-time Listener

    func listenToPost(postId: String, completion: @escaping (Result<Post, Error>) -> Void) -> ListenerRegistration {
        return db.collection(postsCollection).document(postId).addSnapshotListener { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let snapshot = snapshot, snapshot.exists else {
                completion(.failure(FirestorePostError.postNotFound))
                return
            }

            do {
                let post = try snapshot.data(as: Post.self)
                completion(.success(post))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func listenToUserPosts(userId: String, limit: Int = 20, completion: @escaping (Result<[Post], Error>) -> Void) -> ListenerRegistration {
        return db.collection(postsCollection)
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }

                do {
                    let posts = try snapshot.documents.compactMap { try $0.data(as: Post.self) }
                    completion(.success(posts))
                } catch {
                    completion(.failure(error))
                }
            }
    }

    // MARK: - Discovery Channels

    /// Get channels ordered by latest post date (denormalization-free)
    func getDiscoveryChannels(limit: Int = 20) async throws -> [Channel] {
        print("📥 [PostManager] getDiscoveryChannels - limit: \(limit), FORCING SERVER FETCH")

        // Get all block-related users (both blocked and who blocked me)
        let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []
        print("📥 [PostManager] Block-related users count: \(blockedUserIds.count)")

        // Get recent posts to find active channels - BYPASS CACHE
        let postsSnapshot = try await db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: 100) // Get enough posts to find unique channels
            .getDocuments(source: .server) // FORCE SERVER FETCH

        print("📥 [PostManager] Fetched \(postsSnapshot.documents.count) posts from SERVER")

        // Group posts by channelId and find latest post for each channel
        // Use array to maintain order
        var channelLatestPostsArray: [(channelId: String, date: Date)] = []
        var seenChannels = Set<String>()
        var postsWithoutChannel = 0

        for document in postsSnapshot.documents {
            if let post = try? document.data(as: Post.self) {
                // Skip posts from block-related users (both directions)
                if blockedUserIds.contains(post.userId) {
                    continue
                }

                if let channelId = post.channelId {
                    // Only keep the first (latest) post for each channel
                    if !seenChannels.contains(channelId) {
                        seenChannels.insert(channelId)
                        channelLatestPostsArray.append((channelId: channelId, date: post.createdAt))
                    }
                } else {
                    postsWithoutChannel += 1
                }
            }
        }

        print("📥 [PostManager] Posts without channelId: \(postsWithoutChannel)/\(postsSnapshot.documents.count)")
        print("📥 [PostManager] Unique channels found: \(seenChannels.count)")

        // Sort channels by latest post date and maintain stable order
        let sortedChannelData = channelLatestPostsArray
            .sorted { first, second in
                // Primary sort: by date descending
                if first.date != second.date {
                    return first.date > second.date
                }
                // Secondary sort: by channelId for stable ordering when dates are equal
                return first.channelId < second.channelId
            }
            .prefix(limit)

        let sortedChannelIds = sortedChannelData.map { $0.channelId }

        // Fetch channel documents
        print("📥 [PostManager] Fetching \(sortedChannelIds.count) channel documents from SERVER")
        var channels: [Channel] = []
        for channelId in sortedChannelIds {
            if let channelDoc = try? await db.collection("channels").document(channelId).getDocument(source: .server),
               var channel = try? channelDoc.data(as: Channel.self) {
                // Skip channels owned by block-related users (both directions)
                if blockedUserIds.contains(channel.userId) {
                    continue
                }

                // Check if current user is following
                if let currentUserId = Auth.auth().currentUser?.uid {
                    let isFollowing = try await FirestoreChannelManager.shared.checkIfFollowing(channelId: channelId, userId: currentUserId)
                    channel.isFollowing = isFollowing
                }

                // Get follower count dynamically
                channel.followerCount = try? await FirestoreChannelManager.shared.getFollowerCount(channelId: channelId)

                channels.append(channel)
            }
        }

        print("✅ [PostManager] getDiscoveryChannels returning \(channels.count) channels (after bi-directional blocking filter)")
        return channels
    }
}

// Helper extension for chunking arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Channel Manager

enum ChannelError: Error {
    case notAuthenticated
    case channelNotFound
    case invalidData
    case unknown
}

@MainActor
class FirestoreChannelManager {
    static let shared = FirestoreChannelManager()
    private let db = Firestore.firestore()
    private let channelsCollection = "channels"
    private let channelFollowsCollection = "channelFollows"

    private init() {}

    // MARK: - Create Channel

    func createChannel(name: String) async throws -> Channel {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        guard let userId = currentUser.uid as String? else {
            throw ChannelError.invalidData
        }

        // チャンネルにはuserIdのみを保存（ユーザー情報は動的に取得）
        var channel = Channel(
            userId: userId,
            name: name
        )

        let docRef = try db.collection(channelsCollection).addDocument(from: channel)
        channel.id = docRef.documentID

        print("✅ Channel created: \(docRef.documentID)")

        return channel
    }

    // MARK: - Get Channels

    /// Get user's channels
    func getUserChannels(userId: String, forceRefresh: Bool = false) async throws -> [Channel] {
        let snapshot = try await db.collection(channelsCollection)
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: forceRefresh ? .server : .default)

        var channels: [Channel] = []
        for document in snapshot.documents {
            if var channel = try? document.data(as: Channel.self) {
                // Check if current user is following
                if let currentUserId = Auth.auth().currentUser?.uid {
                    let isFollowing = try await checkIfFollowing(channelId: channel.id ?? "", userId: currentUserId)
                    channel.isFollowing = isFollowing
                }

                // Get follower count dynamically
                if let channelId = channel.id {
                    channel.followerCount = try? await getFollowerCount(channelId: channelId)
                }

                channels.append(channel)
            }
        }

        return channels
    }

    /// Get channel by ID
    func getChannel(channelId: String) async throws -> Channel {
        let document = try await db.collection(channelsCollection).document(channelId).getDocument()

        guard var channel = try? document.data(as: Channel.self) else {
            throw ChannelError.channelNotFound
        }

        // Check if current user is following
        if let currentUserId = Auth.auth().currentUser?.uid {
            let isFollowing = try await checkIfFollowing(channelId: channelId, userId: currentUserId)
            channel.isFollowing = isFollowing
        }

        // Get follower count dynamically
        channel.followerCount = try? await getFollowerCount(channelId: channelId)

        return channel
    }

    /// Get followed channels for user
    func getFollowedChannels(userId: String, forceRefresh: Bool = false) async throws -> [Channel] {
        // Get list of followed channel IDs
        let followSnapshot = try await db.collection("users")
            .document(userId)
            .collection("followingChannels")
            .order(by: "followedAt", descending: true)
            .getDocuments(source: forceRefresh ? .server : .default)

        let channelIds = followSnapshot.documents.compactMap { $0.documentID }

        guard !channelIds.isEmpty else {
            return []
        }

        // Firestore 'in' query limit is 10, so batch if needed
        var channels: [Channel] = []
        let batches = channelIds.chunked(into: 10)

        for batch in batches {
            let snapshot = try await db.collection(channelsCollection)
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments(source: forceRefresh ? .server : .default)

            for document in snapshot.documents {
                if var channel = try? document.data(as: Channel.self) {
                    channel.isFollowing = true

                    // Get follower count dynamically
                    if let channelId = channel.id {
                        channel.followerCount = try? await getFollowerCount(channelId: channelId)
                    }

                    channels.append(channel)
                }
            }
        }

        // Sort by latest post date
        channels.sort { ($0.latestPostAt ?? Date.distantPast) > ($1.latestPostAt ?? Date.distantPast) }

        return channels
    }

    /// DEPRECATED: Use FirestoreChannelManager.shared.getRandomChannels() instead
    /// This old implementation used .shuffled() which caused unstable ordering

    // MARK: - Update Channel

    func updateChannel(channelId: String, name: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        // Verify ownership
        let channel = try await getChannel(channelId: channelId)
        guard channel.userId == currentUser.uid else {
            throw ChannelError.notAuthenticated
        }

        try await db.collection(channelsCollection).document(channelId).updateData([
            "name": name,
            "updatedAt": Timestamp(date: Date())
        ])

        print("✅ Channel updated: \(channelId)")
    }

    /// Update channel's latest post info (called when post is created)
    func updateChannelLatestPost(channelId: String, postId: String, artworkUrl: String?) async throws {
        try await db.collection(channelsCollection).document(channelId).updateData([
            "latestPostId": postId,
            "latestPostAt": Timestamp(date: Date()),
            "latestPostArtworkUrl": artworkUrl as Any? ?? NSNull(),
            "updatedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Delete Channel

    func deleteChannel(channelId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        // Verify ownership
        let channel = try await getChannel(channelId: channelId)
        guard channel.userId == currentUser.uid else {
            throw ChannelError.notAuthenticated
        }

        // Delete all posts in channel
        let posts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId, limit: 1000)
        for post in posts {
            if let postId = post.id {
                try? await FirestorePostManager.shared.deletePost(postId: postId)
            }
        }
        print("✅ Deleted \(posts.count) posts from channel")

        // Delete all channel follows from users' followingChannels
        let followersSnapshot = try await db.collection(channelFollowsCollection)
            .document(channelId)
            .collection("followers")
            .getDocuments()

        let batch = db.batch()
        for followerDoc in followersSnapshot.documents {
            let followerId = followerDoc.documentID

            // Delete from user's followingChannels
            let userFollowingRef = db.collection("users")
                .document(followerId)
                .collection("followingChannels")
                .document(channelId)
            batch.deleteDocument(userFollowingRef)

            // Delete from channel's followers
            batch.deleteDocument(followerDoc.reference)
        }

        // Delete channel document
        let channelRef = db.collection(channelsCollection).document(channelId)
        batch.deleteDocument(channelRef)

        try await batch.commit()

        print("✅ Channel deleted: \(channelId)")
    }

    // MARK: - Follow/Unfollow

    func followChannel(channelId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw ChannelError.notAuthenticated
        }

        let batch = db.batch()

        // Add to user's following list
        let userFollowingRef = db.collection("users")
            .document(currentUserId)
            .collection("followingChannels")
            .document(channelId)

        batch.setData([
            "followedAt": Timestamp(date: Date())
        ], forDocument: userFollowingRef)

        // Add to channel's followers list
        let channelFollowerRef = db.collection(channelFollowsCollection)
            .document(channelId)
            .collection("followers")
            .document(currentUserId)

        batch.setData([
            "followedAt": Timestamp(date: Date())
        ], forDocument: channelFollowerRef)

        try await batch.commit()

        print("✅ Followed channel: \(channelId)")

        // Create notification for channel owner
        do {
            let channel = try await getChannel(channelId: channelId)
            if channel.userId != currentUserId, // Don't notify yourself
               let currentUser = try? await FirestoreUserManager.shared.getUser(userId: currentUserId) {
                let notification = Notification(
                    from: currentUser,
                    recipientId: channel.userId,
                    type: .channelFollow,
                    postId: channelId, // Store channelId in postId field
                    artworkUrl: channel.latestPostArtworkUrl
                )
                try? await FirestoreNotificationManager.shared.createNotification(notification)
            }
        } catch {
            print("⚠️ Failed to create channel follow notification: \(error)")
        }
    }

    func unfollowChannel(channelId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw ChannelError.notAuthenticated
        }

        let batch = db.batch()

        // Remove from user's following list
        let userFollowingRef = db.collection("users")
            .document(currentUserId)
            .collection("followingChannels")
            .document(channelId)

        batch.deleteDocument(userFollowingRef)

        // Remove from channel's followers list
        let channelFollowerRef = db.collection(channelFollowsCollection)
            .document(channelId)
            .collection("followers")
            .document(currentUserId)

        batch.deleteDocument(channelFollowerRef)

        try await batch.commit()

        print("✅ Unfollowed channel: \(channelId)")
    }

    func checkIfFollowing(channelId: String, userId: String) async throws -> Bool {
        let document = try await db.collection("users")
            .document(userId)
            .collection("followingChannels")
            .document(channelId)
            .getDocument()

        return document.exists
    }

    /// Get follower count for a channel by counting documents in channelFollows/{channelId}/followers
    func getFollowerCount(channelId: String) async throws -> Int {
        let snapshot = try await db.collection(channelFollowsCollection)
            .document(channelId)
            .collection("followers")
            .getDocuments()

        return snapshot.documents.count
    }
}
