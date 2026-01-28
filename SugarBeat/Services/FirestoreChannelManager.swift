import Foundation
import FirebaseFirestore
import FirebaseAuth

enum ChannelError: Error {
    case notAuthenticated
    case channelNotFound
    case invalidData
    case notAuthorized
    case cannotDeleteChannelWithMembers
    case unknown
}

class FirestoreChannelManager {
    static let shared = FirestoreChannelManager()
    private let db = Firestore.firestore()
    private let channelsCollection = "channels"
    private let channelFollowsCollection = "channelFollows"

    private init() {}

    // MARK: - Create Channel

    func createChannel(name: String, channelType: ChannelType = .personal, accessType: ChannelAccessType = .`public`) async throws -> Channel {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        guard let userId = currentUser.uid as String? else {
            throw ChannelError.invalidData
        }

        // チャンネルにはuserIdのみを保存（ユーザー情報は動的に取得）
        var channel = Channel(
            userId: userId,
            name: name,
            channelType: channelType,
            accessType: accessType
        )

        let docRef = try db.collection(channelsCollection).addDocument(from: channel)
        channel.id = docRef.documentID

        print("✅ Channel created: \(docRef.documentID) - Type: \(channelType.rawValue)")

        return channel
    }

    // MARK: - Channel Permissions

    /// Check if a user can post to a channel
    func canPostToChannel(channelId: String, userId: String) async throws -> Bool {
        let channel = try await getChannel(channelId: channelId)

        switch channel.channelType {
        case .personal:
            // Only owner can post to personal channels
            return channel.userId == userId
        case .shared:
            // Members (followers) can post to shared channels
            // Also check if user is the owner
            if channel.userId == userId {
                return true
            }
            return try await checkIfFollowing(channelId: channelId, userId: userId)
        }
    }

    /// Leave a channel and delete all user's posts in that channel
    func leaveChannelAndDeletePosts(channelId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw ChannelError.notAuthenticated
        }

        print("🚪 [ChannelManager] User \(currentUserId) leaving channel \(channelId)")

        // 1. Get all user's posts in this channel
        let posts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId, userId: currentUserId)
        print("📋 [ChannelManager] Found \(posts.count) posts to delete")

        // 2. Delete each post (likes/comments will be auto-deleted by deletePost)
        for post in posts {
            if let postId = post.id {
                try await FirestorePostManager.shared.deletePost(postId: postId)
                print("🗑️ [ChannelManager] Deleted post \(postId)")
            }
        }

        // 3. Unfollow the channel
        try await unfollowChannel(channelId: channelId)
        print("✅ [ChannelManager] User left channel and deleted \(posts.count) posts")
    }

    // MARK: - Get Channels

    /// Get user's channels
    func getUserChannels(userId: String, forceRefresh: Bool = false) async throws -> [Channel] {
        print("🔍 [ChannelManager] getUserChannels - userId: \(userId), forceRefresh: \(forceRefresh)")

        // Check cache first
        if !forceRefresh, let cachedChannels = FirestoreCacheManager.shared.getCachedUserChannels(userId: userId) {
            print("✅ [ChannelManager] Returning cached user channels: \(cachedChannels.count)")
            return cachedChannels
        }

        let snapshot = try await db.collection(channelsCollection)
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments(source: forceRefresh ? .server : .default)

        var channels: [Channel] = []
        let channelIds: [String] = snapshot.documents.compactMap { $0.documentID }

        for document in snapshot.documents {
            if var channel = try? document.data(as: Channel.self) {
                channels.append(channel)
            }
        }

        // Batch fetch following status and follower counts
        if let currentUserId = Auth.auth().currentUser?.uid {
            let (followingMap, followerCountMap) = try await batchFetchChannelMetadata(channelIds: channelIds, currentUserId: currentUserId)

            for i in 0..<channels.count {
                if let channelId = channels[i].id {
                    channels[i].isFollowing = followingMap[channelId] ?? false
                    channels[i].followerCount = followerCountMap[channelId] ?? 0
                }
            }
        }

        // Cache the result
        FirestoreCacheManager.shared.cacheUserChannels(userId: userId, channels: channels)

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

        // Check cache first
        if !forceRefresh, let cachedChannels = FirestoreCacheManager.shared.getCachedFollowedChannels(userId: userId) {
            print("✅ [ChannelManager] Returning cached followed channels: \(cachedChannels.count)")
            return cachedChannels
        }

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
                    channels.append(channel)
                }
            }
        }

        // Batch fetch follower counts (they're already following, so no need to check)
        if let currentUserId = Auth.auth().currentUser?.uid {
            let (_, followerCountMap) = try await batchFetchChannelMetadata(channelIds: channelIds, currentUserId: currentUserId)

            for i in 0..<channels.count {
                channels[i].isFollowing = true
                if let channelId = channels[i].id {
                    channels[i].followerCount = followerCountMap[channelId] ?? 0
                }
            }
        }

        // Sort by latest post date
        channels.sort { ($0.latestPostAt ?? Date.distantPast) > ($1.latestPostAt ?? Date.distantPast) }

        // Cache the result
        FirestoreCacheManager.shared.cacheFollowedChannels(userId: userId, channels: channels)

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
               let channelId = post.channelId {
                // Only keep the first (latest) post for each channel
                if !seenChannels.contains(channelId) {
                    seenChannels.insert(channelId)
                    channelLatestPostsArray.append((channelId: channelId, date: post.createdAt))
                    print("📊 [ChannelManager] Channel \(channelId): latest post at \(post.createdAt)")
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
        try await updateChannelName(channelId: channelId, name: name)
    }

    /// Update channel name (owner only)
    func updateChannelName(channelId: String, name: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        // Verify ownership
        let channel = try await getChannel(channelId: channelId)
        guard channel.userId == currentUser.uid else {
            throw ChannelError.notAuthorized
        }

        try await db.collection(channelsCollection).document(channelId).updateData([
            "name": name,
            "updatedAt": Timestamp(date: Date())
        ])

        print("✅ Channel name updated: \(channelId) -> \(name)")
    }

    /// Update channel access type (owner only)
    func updateAccessType(channelId: String, accessType: ChannelAccessType) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        // Verify ownership
        let channel = try await getChannel(channelId: channelId)
        guard channel.userId == currentUser.uid else {
            throw ChannelError.notAuthorized
        }

        try await db.collection(channelsCollection).document(channelId).updateData([
            "accessType": accessType.rawValue,
            "updatedAt": Timestamp(date: Date())
        ])

        print("✅ Channel access type updated: \(channelId) -> \(accessType.rawValue)")
    }

    /// Kick a member from the channel (owner only)
    func kickMember(channelId: String, userId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw ChannelError.notAuthenticated
        }

        // Verify ownership
        let channel = try await getChannel(channelId: channelId)
        guard channel.userId == currentUser.uid else {
            throw ChannelError.notAuthorized
        }

        // Cannot kick yourself
        guard userId != currentUser.uid else {
            throw ChannelError.invalidData
        }

        print("👢 [ChannelManager] Owner \(currentUser.uid) kicking user \(userId) from channel \(channelId)")

        // 1. Get all kicked user's posts in this channel
        let posts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId, userId: userId)
        print("📋 [ChannelManager] Found \(posts.count) posts by user \(userId) to delete")

        // 2. Delete each post
        for post in posts {
            if let postId = post.id {
                try await FirestorePostManager.shared.deletePost(postId: postId)
                print("🗑️ [ChannelManager] Deleted post \(postId)")
            }
        }

        // 3. Remove user's follow relationship
        let batch = db.batch()

        // Remove from user's followingChannels
        let userFollowingRef = db.collection("users")
            .document(userId)
            .collection("followingChannels")
            .document(channelId)
        batch.deleteDocument(userFollowingRef)

        // Remove from channel's followers
        let channelFollowerRef = db.collection(channelFollowsCollection)
            .document(channelId)
            .collection("followers")
            .document(userId)
        batch.deleteDocument(channelFollowerRef)

        try await batch.commit()
        print("✅ [ChannelManager] User \(userId) kicked from channel and \(posts.count) posts deleted")
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
            throw ChannelError.notAuthorized
        }

        // Check if there are other members (followers excluding owner)
        let followerCount = try await getFollowerCount(channelId: channelId)

        // If channel is shared and has other members, cannot delete
        if channel.channelType == .shared && followerCount > 0 {
            // Check if owner is also a follower (owner might follow their own channel)
            let ownerIsFollower = try await checkIfFollowing(channelId: channelId, userId: currentUser.uid)
            let otherMembersCount = ownerIsFollower ? followerCount - 1 : followerCount

            if otherMembersCount > 0 {
                print("❌ [ChannelManager] Cannot delete channel with \(otherMembersCount) other members")
                throw ChannelError.cannotDeleteChannelWithMembers
            }
        }

        print("🗑️ [ChannelManager] Deleting channel \(channelId)")

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
                    channelName: channel.name,
                    channelType: channel.channelType.rawValue
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

    /// Batch fetch channel metadata (following status and follower counts)
    /// Returns a tuple of (followingMap, followerCountMap)
    private func batchFetchChannelMetadata(channelIds: [String], currentUserId: String) async throws -> ([String: Bool], [String: Int]) {
        guard !channelIds.isEmpty else {
            return ([:], [:])
        }

        // Fetch all following statuses in parallel
        async let followingTask: [String: Bool] = {
            let followingSnapshot = try await self.db.collection("users")
                .document(currentUserId)
                .collection("followingChannels")
                .getDocuments()

            var followingMap: [String: Bool] = [:]
            for doc in followingSnapshot.documents {
                followingMap[doc.documentID] = true
            }
            return followingMap
        }()

        // Fetch all follower counts in parallel
        async let followerCountTask: [String: Int] = {
            var followerCountMap: [String: Int] = [:]

            // Use Task Group for parallel fetching
            await withTaskGroup(of: (String, Int).self) { group in
                for channelId in channelIds {
                    group.addTask {
                        let count = (try? await self.getFollowerCount(channelId: channelId)) ?? 0
                        return (channelId, count)
                    }
                }

                for await (channelId, count) in group {
                    followerCountMap[channelId] = count
                }
            }

            return followerCountMap
        }()

        let (followingMap, followerCountMap) = try await (followingTask, followerCountTask)
        return (followingMap, followerCountMap)
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

    /// Get list of follower user IDs for a channel
    func getChannelFollowers(channelId: String) async throws -> [String] {
        let snapshot = try await db.collection(channelFollowsCollection)
            .document(channelId)
            .collection("followers")
            .getDocuments()

        return snapshot.documents.map { $0.documentID }
    }

    /// Search channels by name (case-insensitive prefix match)
    func searchChannels(query: String, limit: Int = 50) async throws -> [Channel] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmedQuery.isEmpty else {
            return []
        }

        // Firestore doesn't support case-insensitive search or LIKE queries
        // We'll fetch all channels and filter client-side for better UX
        // For production with many channels, consider using Algolia or similar
        let snapshot = try await db.collection(channelsCollection)
            .order(by: "createdAt", descending: true)
            .limit(to: 500) // Limit to recent channels
            .getDocuments()

        var channels: [Channel] = []
        for document in snapshot.documents {
            if var channel = try? document.data(as: Channel.self) {
                // Case-insensitive partial match
                if channel.name.lowercased().contains(trimmedQuery) {
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
        }

        // Sort by relevance: exact match first, then by follower count
        channels.sort { first, second in
            let firstExact = first.name.lowercased() == trimmedQuery
            let secondExact = second.name.lowercased() == trimmedQuery

            if firstExact && !secondExact {
                return true
            } else if !firstExact && secondExact {
                return false
            } else {
                // Both exact or both not exact, sort by follower count
                return (first.followerCount ?? 0) > (second.followerCount ?? 0)
            }
        }

        return Array(channels.prefix(limit))
    }
}
