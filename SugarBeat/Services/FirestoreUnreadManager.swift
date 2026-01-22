import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manages unread posts tracking in Firestore
/// Each user has a subcollection "readPosts" that tracks which posts they have viewed
class FirestoreUnreadManager {
    static let shared = FirestoreUnreadManager()
    private let db = Firestore.firestore()
    private let usersCollection = "users"

    private init() {}

    // MARK: - Mark Post as Read

    func markPostAsRead(postId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        let readPostRef = db.collection(usersCollection)
            .document(currentUserId)
            .collection("readPosts")
            .document(postId)

        try await readPostRef.setData([
            "readAt": FieldValue.serverTimestamp()
        ])
    }

    func markPostsAsRead(_ postIds: [String]) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        let batch = db.batch()

        for postId in postIds {
            let readPostRef = db.collection(usersCollection)
                .document(currentUserId)
                .collection("readPosts")
                .document(postId)

            batch.setData(["readAt": FieldValue.serverTimestamp()], forDocument: readPostRef)
        }

        try await batch.commit()
    }

    // MARK: - Mark User's Posts as Viewed

    /// Mark all posts from a specific user as viewed
    func markUserPostsAsViewed(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        // Get all posts from the user
        let postsSnapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        let postIds = postsSnapshot.documents.map { $0.documentID }

        // Mark them as read
        try await markPostsAsRead(postIds)
    }

    // MARK: - Check Read Status

    func isPostRead(postId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        let readPostDoc = try await db.collection(usersCollection)
            .document(currentUserId)
            .collection("readPosts")
            .document(postId)
            .getDocument()

        return readPostDoc.exists
    }

    // MARK: - Get Unread Posts Count

    /// Get unread posts count from a specific user
    func getUnreadPostCount(fromUserId: String) async throws -> Int {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return 0
        }

        // Get all posts from the user
        let postsSnapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: fromUserId)
            .getDocuments()

        // Get read posts
        let readPostsSnapshot = try await db.collection(usersCollection)
            .document(currentUserId)
            .collection("readPosts")
            .getDocuments()

        let readPostIds = Set(readPostsSnapshot.documents.map { $0.documentID })
        let allPostIds = Set(postsSnapshot.documents.map { $0.documentID })

        // Calculate unread count
        let unreadCount = allPostIds.subtracting(readPostIds).count

        return unreadCount
    }

    /// Get unread counts for multiple users (for stories bar)
    func getUnreadPostCounts(forUserIds userIds: [String]) async throws -> [String: Int] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return [:]
        }

        var unreadCounts: [String: Int] = [:]

        // Get read posts
        let readPostsSnapshot = try await db.collection(usersCollection)
            .document(currentUserId)
            .collection("readPosts")
            .getDocuments()

        let readPostIds = Set(readPostsSnapshot.documents.map { $0.documentID })

        // For each user, count unread posts
        for userId in userIds {
            let postsSnapshot = try await db.collection("posts")
                .whereField("userId", isEqualTo: userId)
                .getDocuments()

            let userPostIds = Set(postsSnapshot.documents.map { $0.documentID })
            let unreadCount = userPostIds.subtracting(readPostIds).count

            unreadCounts[userId] = unreadCount
        }

        return unreadCounts
    }

    // MARK: - Get Unread Posts

    func getUnreadPosts(fromUserId: String, limit: Int = 20) async throws -> [Post] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }

        // Get all posts from the user
        let postsSnapshot = try await db.collection("posts")
            .whereField("userId", isEqualTo: fromUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit * 2) // Get more to filter
            .getDocuments()

        var allPosts = try postsSnapshot.documents.compactMap { try $0.data(as: Post.self) }

        // Get read posts
        let readPostsSnapshot = try await db.collection(usersCollection)
            .document(currentUserId)
            .collection("readPosts")
            .getDocuments()

        let readPostIds = Set(readPostsSnapshot.documents.map { $0.documentID })

        // Filter unread posts
        allPosts = allPosts.filter { post in
            guard let postId = post.id else { return false }
            return !readPostIds.contains(postId)
        }

        return Array(allPosts.prefix(limit))
    }

    // MARK: - Clear Old Read Posts (Cleanup)

    /// Clear read posts older than X days to prevent subcollection from growing too large
    func clearOldReadPosts(olderThanDays days: Int = 30) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let snapshot = try await db.collection(usersCollection)
            .document(currentUserId)
            .collection("readPosts")
            .whereField("readAt", isLessThan: Timestamp(date: cutoffDate))
            .getDocuments()

        let batch = db.batch()

        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }

        try await batch.commit()
        print("✅ Cleared \(snapshot.documents.count) old read posts")
    }
}
