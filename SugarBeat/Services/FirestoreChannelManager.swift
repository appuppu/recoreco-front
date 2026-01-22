import Foundation
import FirebaseFirestore
import FirebaseAuth

enum ChannelError: Error {
    case notAuthenticated
    case channelNotFound
    case invalidData
    case unknown
}

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
        print("🔍 [ChannelManager] getUserChannels - userId: \(userId), forceRefresh: \(forceRefresh)")
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
        print("🔍 [ChannelManager] getFollowedChannels - userId: \(userId), forceRefresh: \(forceRefresh)")
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

    // MARK: - Discovery Channels

    /// Get channels ordered by latest post date (denormalization-free)
    /// THIS IS THE NEW STABLE-ORDER IMPLEMENTATION
    func getDiscoveryChannels(limit: Int = 20) async throws -> [Channel] {
        print("🚨🚨🚨 NEW CODE EXECUTING 🚨🚨🚨")
        print("🔍 [ChannelManager] ========== getRandomChannels START ==========")
        print("🔍 [ChannelManager] Limit: \(limit)")

        // Get recent posts to find active channels - BYPASS CACHE
        let postsSnapshot = try await db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: 100) // Get enough posts to find unique channels
            .getDocuments(source: .server) // FORCE SERVER FETCH

        print("📊 [ChannelManager] Fetched \(postsSnapshot.documents.count) recent posts from SERVER")

        // Group posts by channelId and find latest post for each channel
        // Use array to maintain order
        var channelLatestPostsArray: [(channelId: String, date: Date)] = []
        var seenChannels = Set<String>()

        for document in postsSnapshot.documents {
            if let post = try? document.data(as: Post.self),
               let channelId = post.channelId,
               let createdAt = post.createdAt {
                // Only keep the first (latest) post for each channel
                if !seenChannels.contains(channelId) {
                    seenChannels.insert(channelId)
                    channelLatestPostsArray.append((channelId: channelId, date: createdAt))
                    print("📊 [ChannelManager] Channel \(channelId): latest post at \(createdAt)")
                }
            }
        }

        print("📊 [ChannelManager] Found \(channelLatestPostsArray.count) unique channels")

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

        print("📊 [ChannelManager] Sorted channel data:")
        for (index, data) in sortedChannelData.enumerated() {
            print("  \(index + 1). \(data.channelId) at \(data.date)")
        }

        // Fetch channel documents
        var channels: [Channel] = []
        for channelId in sortedChannelIds {
            if let channelDoc = try? await db.collection(channelsCollection).document(channelId).getDocument(),
               var channel = try? channelDoc.data(as: Channel.self) {
                // Check if current user is following
                if let currentUserId = Auth.auth().currentUser?.uid {
                    let isFollowing = try await checkIfFollowing(channelId: channelId, userId: currentUserId)
                    channel.isFollowing = isFollowing
                }

                // Get follower count dynamically
                channel.followerCount = try? await getFollowerCount(channelId: channelId)

                channels.append(channel)
            } else {
                print("⚠️ [ChannelManager] Failed to fetch channel document for \(channelId)")
            }
        }

        print("✅ [ChannelManager] Returning \(channels.count) channels in order: \(channels.map { $0.name })")
        return channels
    }

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
            "latestPostArtworkUrl": artworkUrl ?? NSNull(),
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
                    artworkUrl: channel.latestPostArtworkUrl,
                    channelName: channel.name
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

// MARK: - Helper Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
