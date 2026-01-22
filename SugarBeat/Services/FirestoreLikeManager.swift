import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreLikeManager {
    static let shared = FirestoreLikeManager()
    private let db = Firestore.firestore()
    private let postsCollection = "posts"

    private init() {}

    // MARK: - Like Post

    func likePost(postId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        let likeRef = db.collection(postsCollection)
            .document(postId)
            .collection("likes")
            .document(currentUserId)

        // Check if already liked
        let document = try await likeRef.getDocument()
        guard !document.exists else {
            return // Already liked
        }

        // Add like (no batch needed since we're not updating post document)
        try await likeRef.setData(["createdAt": FieldValue.serverTimestamp()])
        print("✅ Liked post: \(postId)")

        // Create notification
        let post = try await FirestorePostManager.shared.getPost(postId: postId)
        if post.userId != currentUserId, // Don't notify yourself
           let currentUser = try? await FirestoreUserManager.shared.getUser(userId: currentUserId) {
            let notification = Notification(
                from: currentUser,
                recipientId: post.userId,
                type: .like,
                postId: postId,
                artworkUrl: post.artworkUrl
            )
            try? await FirestoreNotificationManager.shared.createNotification(notification)
        }
    }

    // MARK: - Unlike Post

    func unlikePost(postId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        let likeRef = db.collection(postsCollection)
            .document(postId)
            .collection("likes")
            .document(currentUserId)

        // Remove like (no batch needed since we're not updating post document)
        try await likeRef.delete()
        print("✅ Unliked post: \(postId)")
    }

    // MARK: - Check Like Status

    func isPostLiked(postId: String, userId: String) async throws -> Bool {
        do {
            let document = try await db.collection(postsCollection)
                .document(postId)
                .collection("likes")
                .document(userId)
                .getDocument()

            return document.exists
        } catch {
            return false
        }
    }

    // MARK: - Get Post Likes

    func getPostLikes(postId: String, limit: Int = 50) async throws -> [String] {
        do {
            let snapshot = try await db.collection(postsCollection)
                .document(postId)
                .collection("likes")
                .limit(to: limit)
                .order(by: "createdAt", descending: true)
                .getDocuments()

            return snapshot.documents.map { $0.documentID }
        } catch {
            throw error
        }
    }

    // MARK: - Real-time Listener

    func listenToPostLikes(postId: String, completion: @escaping (Result<Int, Error>) -> Void) -> ListenerRegistration {
        return db.collection(postsCollection)
            .document(postId)
            .collection("likes")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot else {
                    completion(.success(0))
                    return
                }

                completion(.success(snapshot.documents.count))
            }
    }
}
