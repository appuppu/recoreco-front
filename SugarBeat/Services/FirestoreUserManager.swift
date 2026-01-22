import Foundation
import FirebaseFirestore
import FirebaseAuth

enum FirestoreUserError: Error {
    case userNotFound
    case invalidData
    case createFailed(Error)
    case updateFailed(Error)
    case deleteFailed(Error)
    case searchFailed(Error)
    case notAuthenticated

    var localizedDescription: String {
        switch self {
        case .userNotFound:
            return "ユーザーが見つかりません"
        case .invalidData:
            return "無効なデータです"
        case .createFailed(let error):
            return "作成に失敗しました: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "更新に失敗しました: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "削除に失敗しました: \(error.localizedDescription)"
        case .searchFailed(let error):
            return "検索に失敗しました: \(error.localizedDescription)"
        case .notAuthenticated:
            return "認証が必要です"
        }
    }
}

class FirestoreUserManager {
    static let shared = FirestoreUserManager()
    private let db = Firestore.firestore()
    private let usersCollection = "users"

    private init() {
        // Firestore settings are configured in FirebaseConfig before any access
    }

    // MARK: - Create User

    func createUser(_ user: User) async throws {
        guard let userId = user.id else {
            throw FirestoreUserError.invalidData
        }

        do {
            // Create user data with all required fields for security rules
            let userData: [String: Any] = [
                "username": user.username,
                "email": user.email ?? "",
                "displayName": user.displayName,
                "profileImageUrl": user.profileImageUrl ?? NSNull(),
                "bio": user.bio ?? NSNull(),
                "isPublic": true, // Default to public
                "createdAt": Timestamp(date: user.createdAt),
                "updatedAt": Timestamp(date: user.updatedAt),
                "followingCount": 0,
                "followerCount": 0,
                "postCount": 0
            ]

            try await db.collection(usersCollection).document(userId).setData(userData)
            print("✅ User created: \(userId)")
        } catch {
            throw FirestoreUserError.createFailed(error)
        }
    }

    // MARK: - Get User

    func getUser(userId: String, useCache: Bool = true, fetchCounts: Bool = false) async throws -> User {
        // Check cache first
        if useCache, let cachedUser = FirestoreCacheManager.shared.getCachedUser(userId: userId) {
            print("✅ User loaded from cache: \(userId)")

            // Fetch counts if requested
            if fetchCounts {
                var userWithCounts = cachedUser
                await enrichUserWithCounts(&userWithCounts)
                return userWithCounts
            }

            return cachedUser
        }

        do {
            let document = try await db.collection(usersCollection).document(userId).getDocument()

            guard document.exists else {
                throw FirestoreUserError.userNotFound
            }

            var user = try document.data(as: User.self)
            print("✅ User loaded from Firestore: \(userId)")

            // Fetch counts if requested
            if fetchCounts {
                await enrichUserWithCounts(&user)
            }

            // Cache the user
            FirestoreCacheManager.shared.cacheUser(user)

            return user
        } catch {
            throw FirestoreUserError.userNotFound
        }
    }

    // MARK: - Helper: Enrich User with Counts

    private func enrichUserWithCounts(_ user: inout User) async {
        guard let userId = user.id else { return }

        // Get follower count
        do {
            let followersSnapshot = try await db.collection(usersCollection)
                .document(userId)
                .collection("followers")
                .getDocuments()
            user.followerCount = followersSnapshot.documents.count
        } catch {
            print("⚠️ Failed to get follower count: \(error)")
            user.followerCount = 0
        }

        // Get following count
        do {
            let followingSnapshot = try await db.collection(usersCollection)
                .document(userId)
                .collection("following")
                .getDocuments()
            user.followingCount = followingSnapshot.documents.count
        } catch {
            print("⚠️ Failed to get following count: \(error)")
            user.followingCount = 0
        }

        // Get post count (channel posts only)
        do {
            let postsSnapshot = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .whereField("channelId", isNotEqualTo: NSNull())
                .getDocuments()
            user.postCount = postsSnapshot.documents.count
        } catch {
            print("⚠️ Failed to get post count: \(error)")
            user.postCount = 0
        }
    }

    // MARK: - Batch Get Users (OPTIMIZED - reduces N+1 queries)

    func getUsers(userIds: [String]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }

        var users: [User] = []
        var uncachedIds: [String] = []

        // Check cache first
        for userId in userIds {
            if let cachedUser = FirestoreCacheManager.shared.getCachedUser(userId: userId) {
                users.append(cachedUser)
            } else {
                uncachedIds.append(userId)
            }
        }

        print("✅ Loaded \(users.count) users from cache, fetching \(uncachedIds.count) from Firestore")

        // Fetch uncached users in batches (Firestore 'in' query supports up to 10 values)
        if !uncachedIds.isEmpty {
            let batches = uncachedIds.chunked(into: 10)

            for batch in batches {
                let snapshot = try await db.collection(usersCollection)
                    .whereField(FieldPath.documentID(), in: batch)
                    .getDocuments()

                let fetchedUsers = try snapshot.documents.compactMap { try $0.data(as: User.self) }
                users.append(contentsOf: fetchedUsers)

                // Cache fetched users
                FirestoreCacheManager.shared.cacheUsers(fetchedUsers)
            }
        }

        return users
    }

    func getCurrentUser() async throws -> User {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        return try await getUser(userId: userId)
    }

    // MARK: - Get User by Username

    func getUserByUsername(username: String) async throws -> User? {
        do {
            let snapshot = try await db.collection(usersCollection)
                .whereField("username", isEqualTo: username)
                .limit(to: 1)
                .getDocuments()

            guard let document = snapshot.documents.first else {
                return nil
            }

            let user = try document.data(as: User.self)

            // Cache the user
            FirestoreCacheManager.shared.cacheUser(user)

            return user
        } catch {
            print("❌ Failed to get user by username: \(error)")
            throw FirestoreUserError.searchFailed(error)
        }
    }

    // MARK: - Update User

    func updateUser(_ user: User) async throws {
        guard let userId = user.id else {
            throw FirestoreUserError.invalidData
        }

        do {
            var updateData: [String: Any] = [
                "displayName": user.displayName,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if let bio = user.bio {
                updateData["bio"] = bio
            }

            if let profileImageUrl = user.profileImageUrl {
                updateData["profileImageUrl"] = profileImageUrl
            }

            try await db.collection(usersCollection).document(userId).updateData(updateData)

            // Invalidate cache
            FirestoreCacheManager.shared.invalidateUser(userId: userId)

            print("✅ User updated: \(userId)")
        } catch {
            throw FirestoreUserError.updateFailed(error)
        }
    }

    func updateUserProfile(userId: String, displayName: String, bio: String?, profileImageUrl: String?) async throws {
        do {
            var updateData: [String: Any] = [
                "displayName": displayName,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if let bio = bio {
                updateData["bio"] = bio
            } else {
                updateData["bio"] = FieldValue.delete()
            }

            if let profileImageUrl = profileImageUrl {
                updateData["profileImageUrl"] = profileImageUrl
            } else {
                updateData["profileImageUrl"] = FieldValue.delete()
            }

            try await db.collection(usersCollection).document(userId).updateData(updateData)

            // Invalidate cache
            FirestoreCacheManager.shared.invalidateUser(userId: userId)

            print("✅ User profile updated: \(userId)")
        } catch {
            print("❌ Failed to update user profile: \(error)")
            throw FirestoreUserError.updateFailed(error)
        }
    }

    func updateProfileImage(userId: String, imageUrl: String) async throws {
        do {
            try await db.collection(usersCollection).document(userId).updateData([
                "profileImageUrl": imageUrl,
                "updatedAt": FieldValue.serverTimestamp()
            ])
            print("✅ Profile image updated: \(userId)")
        } catch {
            throw FirestoreUserError.updateFailed(error)
        }
    }

    // MARK: - Delete User

    func deleteUser(userId: String) async throws {
        do {
            print("🗑️ Starting comprehensive user deletion for: \(userId)")

            // 1. Delete user's posts
            print("🗑️ Deleting user's posts...")
            let postsSnapshot = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            for document in postsSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(postsSnapshot.documents.count) posts")

            // 2. Delete user's likes
            print("🗑️ Deleting user's likes...")
            let likesSnapshot = try await db.collection("likes")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            for document in likesSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(likesSnapshot.documents.count) likes")

            // 3. Delete user's comments
            print("🗑️ Deleting user's comments...")
            let commentsSnapshot = try await db.collection("comments")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            for document in commentsSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(commentsSnapshot.documents.count) comments")

            // 4. Delete user's channels
            print("🗑️ Deleting user's channels...")
            let channelsSnapshot = try await db.collection("channels")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            for document in channelsSnapshot.documents {
                // Also delete channel follows
                let channelId = document.documentID
                let channelFollowsSnapshot = try await db.collection("channelFollows")
                    .whereField("channelId", isEqualTo: channelId)
                    .getDocuments()
                for followDoc in channelFollowsSnapshot.documents {
                    try await followDoc.reference.delete()
                }
                try await document.reference.delete()
            }
            print("✅ Deleted \(channelsSnapshot.documents.count) channels")

            // 5. Delete channel follows by this user
            print("🗑️ Deleting user's channel follows...")
            let userChannelFollowsSnapshot = try await db.collection("channelFollows")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()
            for document in userChannelFollowsSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(userChannelFollowsSnapshot.documents.count) channel follows")

            // 6. Delete user follows (where this user is following others)
            print("🗑️ Deleting user's follows...")
            let followsSnapshot = try await db.collection("follows")
                .whereField("followerId", isEqualTo: userId)
                .getDocuments()
            for document in followsSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(followsSnapshot.documents.count) follows")

            // 7. Delete follows where this user is being followed
            print("🗑️ Deleting follows of this user...")
            let followedBySnapshot = try await db.collection("follows")
                .whereField("followingId", isEqualTo: userId)
                .getDocuments()
            for document in followedBySnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(followedBySnapshot.documents.count) followers")

            // 8. Delete blocks created by this user
            print("🗑️ Deleting blocks by this user...")
            let blocksSnapshot = try await db.collection("blocks")
                .whereField("blockerId", isEqualTo: userId)
                .getDocuments()
            for document in blocksSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(blocksSnapshot.documents.count) blocks by user")

            // 9. Delete blocks where this user is blocked
            print("🗑️ Deleting blocks of this user...")
            let blockedSnapshot = try await db.collection("blocks")
                .whereField("blockedId", isEqualTo: userId)
                .getDocuments()
            for document in blockedSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(blockedSnapshot.documents.count) blocks of user")

            // 10. Delete reports by this user
            print("🗑️ Deleting reports by this user...")
            let reportsSnapshot = try await db.collection("reports")
                .whereField("reporterId", isEqualTo: userId)
                .getDocuments()
            for document in reportsSnapshot.documents {
                try await document.reference.delete()
            }
            print("✅ Deleted \(reportsSnapshot.documents.count) reports by user")

            // 11. Finally, delete the user document
            print("🗑️ Deleting user document...")
            try await db.collection(usersCollection).document(userId).delete()
            print("✅ User document deleted: \(userId)")

            print("✅ Comprehensive user deletion completed for: \(userId)")
        } catch {
            print("❌ Failed to delete user: \(error)")
            throw FirestoreUserError.deleteFailed(error)
        }
    }

    // MARK: - Search Users

    func searchUsers(query: String, limit: Int = 20) async throws -> [User] {
        do {
            // Get block-related users (both directions)
            let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []

            let snapshot = try await db.collection(usersCollection)
                .whereField("username", isGreaterThanOrEqualTo: query)
                .whereField("username", isLessThan: query + "\u{f8ff}")
                .limit(to: limit)
                .getDocuments()

            var users = snapshot.documents.compactMap { try? $0.data(as: User.self) }

            // Also search by displayName
            let displayNameSnapshot = try await db.collection(usersCollection)
                .whereField("displayName", isGreaterThanOrEqualTo: query)
                .whereField("displayName", isLessThan: query + "\u{f8ff}")
                .limit(to: limit)
                .getDocuments()

            let displayNameUsers = displayNameSnapshot.documents.compactMap { try? $0.data(as: User.self) }

            // Merge and deduplicate
            users.append(contentsOf: displayNameUsers)
            users = Array(Set(users.compactMap { $0.id }.map { id in users.first { $0.id == id }! }))

            // Filter out block-related users (both directions)
            users = users.filter { user in
                guard let userId = user.id else { return true }
                return !blockedUserIds.contains(userId)
            }

            return Array(users.prefix(limit))
        } catch {
            throw FirestoreUserError.searchFailed(error)
        }
    }

    // MARK: - Check Username Availability

    func checkUsernameAvailability(username: String) async throws -> Bool {
        do {
            let snapshot = try await db.collection(usersCollection)
                .whereField("username", isEqualTo: username)
                .limit(to: 1)
                .getDocuments()

            return snapshot.documents.isEmpty
        } catch {
            throw FirestoreUserError.searchFailed(error)
        }
    }

    // MARK: - Increment/Decrement Counters

    func incrementFollowingCount(userId: String) async throws {
        try await db.collection(usersCollection).document(userId).updateData([
            "followingCount": FieldValue.increment(Int64(1))
        ])
    }

    func decrementFollowingCount(userId: String) async throws {
        try await db.collection(usersCollection).document(userId).updateData([
            "followingCount": FieldValue.increment(Int64(-1))
        ])
    }

    func incrementFollowerCount(userId: String) async throws {
        try await db.collection(usersCollection).document(userId).updateData([
            "followerCount": FieldValue.increment(Int64(1))
        ])
    }

    func decrementFollowerCount(userId: String) async throws {
        try await db.collection(usersCollection).document(userId).updateData([
            "followerCount": FieldValue.increment(Int64(-1))
        ])
    }

    func incrementPostCount(userId: String) async throws {
        try await db.collection(usersCollection).document(userId).updateData([
            "postCount": FieldValue.increment(Int64(1))
        ])
    }

    func decrementPostCount(userId: String) async throws {
        try await db.collection(usersCollection).document(userId).updateData([
            "postCount": FieldValue.increment(Int64(-1))
        ])
    }

    // MARK: - Real-time Listener

    func listenToUser(userId: String, completion: @escaping (Result<User, Error>) -> Void) -> ListenerRegistration {
        return db.collection(usersCollection).document(userId).addSnapshotListener { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let snapshot = snapshot, snapshot.exists else {
                completion(.failure(FirestoreUserError.userNotFound))
                return
            }

            do {
                let user = try snapshot.data(as: User.self)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
