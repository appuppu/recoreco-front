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

        // Add like + increment denormalized likeCount on the post (atomic batch)
        // これにより、フィード表示時に likes サブコレクションを全件カウントせず
        // Post ドキュメントの likeCount を読むだけで済む（読み取り回数を大幅削減）
        let postRef = db.collection(postsCollection).document(postId)
        let batch = db.batch()
        batch.setData(["createdAt": FieldValue.serverTimestamp()], forDocument: likeRef)
        batch.updateData(["likeCount": FieldValue.increment(Int64(1))], forDocument: postRef)
        try await batch.commit()
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

        // Only decrement if the like actually exists (avoid double-decrement /負の値)
        let document = try await likeRef.getDocument()
        guard document.exists else {
            return // Not liked
        }

        // Remove like + decrement denormalized likeCount on the post (atomic batch)
        let postRef = db.collection(postsCollection).document(postId)
        let batch = db.batch()
        batch.deleteDocument(likeRef)
        batch.updateData(["likeCount": FieldValue.increment(Int64(-1))], forDocument: postRef)
        try await batch.commit()
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
