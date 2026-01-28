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
            print("🔍 [FirestorePostManager] Starting createPost...")
            print("   - userId: \(post.userId)")
            print("   - channelId: \(post.channelId ?? "nil")")

            let docRef = try db.collection(postsCollection).addDocument(from: post)
            print("✅ [FirestorePostManager] addDocument succeeded: \(docRef.documentID)")

            // Increment user's post count
            print("🔍 [FirestorePostManager] Incrementing post count for user: \(post.userId)")
            try await FirestoreUserManager.shared.incrementPostCount(userId: post.userId)
            print("✅ [FirestorePostManager] Post count incremented successfully")

            print("✅ [FirestorePostManager] createPost completed successfully")
            return docRef.documentID
        } catch let error as NSError {
            print("❌ [FirestorePostManager] createPost failed:")
            print("   - Error domain: \(error.domain)")
            print("   - Error code: \(error.code)")
            print("   - Error description: \(error.localizedDescription)")
            print("   - Error userInfo: \(error.userInfo)")
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

    /// Get posts by a specific user in a specific channel
    func getChannelPosts(channelId: String, userId: String, limit: Int = 1000) async throws -> [Post] {
        print("📥 [PostManager] getChannelPosts - channelId: \(channelId), userId: \(userId)")
        do {
            let query = db.collection(postsCollection)
                .whereField("channelId", isEqualTo: channelId)
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

            let snapshot = try await query.getDocuments(source: .server)
            print("📥 [PostManager] Fetched \(snapshot.documents.count) posts by user \(userId) in channel \(channelId)")
            let posts = try snapshot.documents.compactMap { try $0.data(as: Post.self) }

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
    func getDiscoveryChannels(channelType: ChannelType? = nil, limit: Int = 20) async throws -> [Channel] {
        print("📥 [PostManager] getDiscoveryChannels - channelType: \(channelType?.rawValue ?? "all"), limit: \(limit), FORCING SERVER FETCH")

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

                // Filter by channel type if specified
                if let channelType = channelType, channel.channelType != channelType {
                    print("📥 [PostManager] Skipping channel \(channelId) - type mismatch: \(channel.channelType.rawValue) != \(channelType.rawValue)")
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

                // Apply limit after filtering
                if channels.count >= limit {
                    break
                }
            }
        }

        print("✅ [PostManager] getDiscoveryChannels returning \(channels.count) channels (after filtering by type: \(channelType?.rawValue ?? "all"))")
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
