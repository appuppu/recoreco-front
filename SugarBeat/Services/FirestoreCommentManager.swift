import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreCommentManager {
    static let shared = FirestoreCommentManager()
    private let db = Firestore.firestore()
    private let postsCollection = "posts"

    private init() {}

    // MARK: - Helper Methods

    /// バッチでコメントにユーザー情報を設定（パフォーマンス最適化）
    private func enrichCommentsWithUserInfo(_ comments: [Comment]) async -> [Comment] {
        // 重複を除いたuserIdリストを取得
        let userIds = Array(Set(comments.map { $0.userId }))

        // バッチでユーザー情報を取得
        guard let users = try? await FirestoreUserManager.shared.getUsers(userIds: userIds) else {
            return comments
        }

        // userIdをキーとした辞書を作成
        let userDict: [String: User] = Dictionary(uniqueKeysWithValues: users.compactMap { user in
            guard let id = user.id else { return nil }
            return (id, user)
        })

        // 各コメントにユーザー情報を設定
        return comments.map { comment in
            var updatedComment = comment
            if let user = userDict[comment.userId] {
                updatedComment.userProfileImageUrl = user.profileImageUrl
            }
            return updatedComment
        }
    }

    /// バッチでコメントに返信数を設定（パフォーマンス最適化）
    private func enrichCommentsWithReplyCount(_ comments: [Comment], postId: String) async -> [Comment] {
        // 各コメントIDに対して返信数を取得
        var replyCounts: [String: Int] = [:]

        // 一度のクエリで全ての返信を取得
        do {
            let snapshot = try await db.collection(postsCollection)
                .document(postId)
                .collection("comments")
                .whereField("parentCommentId", isNotEqualTo: NSNull())
                .getDocuments()

            // 親コメントIDごとに返信数をカウント
            for doc in snapshot.documents {
                if let reply = try? doc.data(as: Comment.self),
                   let parentId = reply.parentCommentId {
                    replyCounts[parentId, default: 0] += 1
                }
            }
        } catch {
            print("Failed to fetch reply counts: \(error)")
        }

        // 各コメントに返信数を設定
        return comments.map { comment in
            var updatedComment = comment
            if let commentId = comment.id {
                updatedComment.replyCount = replyCounts[commentId] ?? 0
            }
            return updatedComment
        }
    }

    /// バッチでコメントにいいね数といいね状態を設定（パフォーマンス最適化）
    private func enrichCommentsWithLikeInfo(_ comments: [Comment], postId: String) async -> [Comment] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return comments
        }

        var likeCounts: [String: Int] = [:]
        var likedByCurrentUser: Set<String> = []

        // コメントIDリストを取得
        let commentIds = comments.compactMap { $0.id }

        // 各コメントのいいねを取得
        for commentId in commentIds {
            do {
                let likesSnapshot = try await db.collection(postsCollection)
                    .document(postId)
                    .collection("comments")
                    .document(commentId)
                    .collection("likes")
                    .getDocuments()

                likeCounts[commentId] = likesSnapshot.documents.count

                // 現在のユーザーがいいねしているか確認
                if likesSnapshot.documents.contains(where: { $0.documentID == currentUserId }) {
                    likedByCurrentUser.insert(commentId)
                }
            } catch {
                print("Failed to fetch likes for comment \(commentId): \(error)")
            }
        }

        // 各コメントにいいね情報を設定
        return comments.map { comment in
            var updatedComment = comment
            if let commentId = comment.id {
                updatedComment.likeCount = likeCounts[commentId] ?? 0
                updatedComment.isLiked = likedByCurrentUser.contains(commentId)
            }
            return updatedComment
        }
    }

    // MARK: - Create Comment

    func createComment(_ comment: Comment) async throws -> String {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        let commentRef = db.collection(postsCollection)
            .document(comment.postId)
            .collection("comments")
            .document()

        // Create comment and increment comment count
        do {
            try commentRef.setData(from: comment)

            // Increment comment count on post
            try await db.collection(postsCollection)
                .document(comment.postId)
                .updateData(["commentCount": FieldValue.increment(Int64(1))])

            // Note: replyCount is calculated dynamically, no need to update parent comment
        } catch {
            throw error
        }

        print("✅ Comment created: \(commentRef.documentID)")

        // Create notification
        let post = try await FirestorePostManager.shared.getPost(postId: comment.postId)
        if post.userId != currentUserId, // Don't notify yourself
           let currentUser = try? await FirestoreUserManager.shared.getUser(userId: currentUserId) {
            let notification = Notification(
                from: currentUser,
                recipientId: post.userId,
                type: .comment,
                postId: comment.postId,
                artworkUrl: post.artworkUrl
            )
            try? await FirestoreNotificationManager.shared.createNotification(notification)
        }

        return commentRef.documentID
    }

    // MARK: - Get Comments

    func getComments(postId: String, limit: Int = 50, lastDocument: DocumentSnapshot? = nil) async throws -> ([Comment], DocumentSnapshot?) {
        do {
            // 全コメントを取得してから、アプリ側でフィルタリング
            // （Firestoreでは「フィールドが存在しないOR null」のクエリが難しいため）
            var query = db.collection(postsCollection)
                .document(postId)
                .collection("comments")
                .order(by: "createdAt", descending: false)  // 古い順
                .limit(to: limit)

            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            var allComments = try snapshot.documents.compactMap { try $0.data(as: Comment.self) }

            // 親コメントのみフィルタリング（parentCommentIdがnilのもの）
            var comments = allComments.filter { $0.parentCommentId == nil }

            // バッチでユーザー情報を設定（パフォーマンス最適化）
            comments = await enrichCommentsWithUserInfo(comments)

            // バッチで返信数を設定（パフォーマンス最適化）
            comments = await enrichCommentsWithReplyCount(comments, postId: postId)

            // バッチでいいね情報を設定（パフォーマンス最適化）
            comments = await enrichCommentsWithLikeInfo(comments, postId: postId)

            let lastDoc = snapshot.documents.last
            return (comments, lastDoc)
        } catch {
            throw error
        }
    }

    // MARK: - Get Replies

    func getReplies(postId: String, parentCommentId: String) async throws -> [Comment] {
        do {
            let snapshot = try await db.collection(postsCollection)
                .document(postId)
                .collection("comments")
                .whereField("parentCommentId", isEqualTo: parentCommentId)
                .order(by: "createdAt", descending: false)
                .getDocuments()

            var replies = try snapshot.documents.compactMap { try $0.data(as: Comment.self) }

            // バッチでユーザー情報を設定
            replies = await enrichCommentsWithUserInfo(replies)

            // バッチでいいね情報を設定
            replies = await enrichCommentsWithLikeInfo(replies, postId: postId)

            return replies
        } catch {
            throw error
        }
    }

    // MARK: - Delete Comment

    func deleteComment(postId: String, commentId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        // Get comment to verify ownership
        let commentRef = db.collection(postsCollection)
            .document(postId)
            .collection("comments")
            .document(commentId)

        let commentDoc = try await commentRef.getDocument()
        guard let comment = try? commentDoc.data(as: Comment.self) else {
            throw FirestorePostError.postNotFound
        }

        // Get post to check if current user is post owner
        let post = try await FirestorePostManager.shared.getPost(postId: postId)

        // Check if user is comment owner or post owner
        guard comment.userId == currentUserId || post.userId == currentUserId else {
            throw FirestorePostError.unauthorized
        }

        // If this is a parent comment, delete all replies first
        var totalDeletedCount = 1  // Include the parent comment itself
        if comment.parentCommentId == nil {
            let repliesSnapshot = try await db.collection(postsCollection)
                .document(postId)
                .collection("comments")
                .whereField("parentCommentId", isEqualTo: commentId)
                .getDocuments()

            // Delete all replies
            for replyDoc in repliesSnapshot.documents {
                try await replyDoc.reference.delete()
                totalDeletedCount += 1
            }
        }

        // Delete the comment itself
        try await commentRef.delete()

        // Decrement comment count on post (by total number of deleted comments)
        try await db.collection(postsCollection)
            .document(postId)
            .updateData(["commentCount": FieldValue.increment(Int64(-totalDeletedCount))])

        print("✅ Comment deleted: \(commentId) (including \(totalDeletedCount - 1) replies)")
    }

    // MARK: - Like/Unlike Comment

    func likeComment(postId: String, commentId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        let likeRef = db.collection(postsCollection)
            .document(postId)
            .collection("comments")
            .document(commentId)
            .collection("likes")
            .document(currentUserId)

        try await likeRef.setData([
            "userId": currentUserId,
            "createdAt": FieldValue.serverTimestamp()
        ])

        print("✅ Comment liked: \(commentId)")
    }

    func unlikeComment(postId: String, commentId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestorePostError.notAuthenticated
        }

        let likeRef = db.collection(postsCollection)
            .document(postId)
            .collection("comments")
            .document(commentId)
            .collection("likes")
            .document(currentUserId)

        try await likeRef.delete()

        print("✅ Comment unliked: \(commentId)")
    }

    // MARK: - Real-time Listener

    func listenToComments(postId: String, completion: @escaping (Result<[Comment], Error>) -> Void) -> ListenerRegistration {
        return db.collection(postsCollection)
            .document(postId)
            .collection("comments")
            .order(by: "createdAt", descending: false)  // 古い順
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot, let self = self else {
                    completion(.success([]))
                    return
                }

                do {
                    let comments = try snapshot.documents.compactMap { try $0.data(as: Comment.self) }

                    // バッチでユーザー情報を設定（リアルタイムリスナー内で非同期処理）
                    Task {
                        let enrichedComments = await self.enrichCommentsWithUserInfo(comments)
                        completion(.success(enrichedComments))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
    }
}
