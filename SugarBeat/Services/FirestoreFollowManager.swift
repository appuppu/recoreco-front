import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreFollowManager {
    static let shared = FirestoreFollowManager()
    private let db = Firestore.firestore()
    private let usersCollection = "users"

    private init() {}

    // MARK: - Follow User

    func followUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        guard currentUserId != userId else {
            return // Cannot follow yourself
        }

        let batch = db.batch()

        // Add to current user's following subcollection
        let followingRef = db.collection(usersCollection)
            .document(currentUserId)
            .collection("following")
            .document(userId)
        batch.setData(["createdAt": FieldValue.serverTimestamp()], forDocument: followingRef)

        // Add to target user's followers subcollection
        let followerRef = db.collection(usersCollection)
            .document(userId)
            .collection("followers")
            .document(currentUserId)
        batch.setData(["createdAt": FieldValue.serverTimestamp()], forDocument: followerRef)

        // Increment counters
        let currentUserRef = db.collection(usersCollection).document(currentUserId)
        batch.updateData(["followingCount": FieldValue.increment(Int64(1))], forDocument: currentUserRef)

        let targetUserRef = db.collection(usersCollection).document(userId)
        batch.updateData(["followerCount": FieldValue.increment(Int64(1))], forDocument: targetUserRef)

        do {
            try await batch.commit()
            print("✅ Followed user: \(userId)")
        } catch {
            throw error
        }
    }

    // MARK: - Unfollow User

    func unfollowUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        let batch = db.batch()

        // Remove from current user's following subcollection
        let followingRef = db.collection(usersCollection)
            .document(currentUserId)
            .collection("following")
            .document(userId)
        batch.deleteDocument(followingRef)

        // Remove from target user's followers subcollection
        let followerRef = db.collection(usersCollection)
            .document(userId)
            .collection("followers")
            .document(currentUserId)
        batch.deleteDocument(followerRef)

        // Decrement counters
        let currentUserRef = db.collection(usersCollection).document(currentUserId)
        batch.updateData(["followingCount": FieldValue.increment(Int64(-1))], forDocument: currentUserRef)

        let targetUserRef = db.collection(usersCollection).document(userId)
        batch.updateData(["followerCount": FieldValue.increment(Int64(-1))], forDocument: targetUserRef)

        do {
            try await batch.commit()
            print("✅ Unfollowed user: \(userId)")
        } catch {
            throw error
        }
    }

    // MARK: - Check Follow Status

    func isFollowing(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        guard currentUserId != userId else {
            return false
        }

        do {
            let document = try await db.collection(usersCollection)
                .document(currentUserId)
                .collection("following")
                .document(userId)
                .getDocument()

            return document.exists
        } catch {
            return false
        }
    }

    func isFollower(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        guard currentUserId != userId else {
            return false
        }

        do {
            let document = try await db.collection(usersCollection)
                .document(currentUserId)
                .collection("followers")
                .document(userId)
                .getDocument()

            return document.exists
        } catch {
            return false
        }
    }

    // MARK: - Get Followers (OPTIMIZED - batch fetch to avoid N+1)

    func getFollowers(userId: String, limit: Int = 50) async throws -> [User] {
        do {
            let snapshot = try await db.collection(usersCollection)
                .document(userId)
                .collection("followers")
                .limit(to: limit)
                .getDocuments()

            let followerIds = snapshot.documents.map { $0.documentID }

            // Batch fetch users (optimized)
            let followers = try await FirestoreUserManager.shared.getUsers(userIds: followerIds)

            return followers
        } catch {
            throw error
        }
    }

    // MARK: - Get Following (OPTIMIZED - batch fetch to avoid N+1)

    func getFollowing(userId: String, limit: Int = 50) async throws -> [User] {
        do {
            let snapshot = try await db.collection(usersCollection)
                .document(userId)
                .collection("following")
                .limit(to: limit)
                .getDocuments()

            let followingIds = snapshot.documents.map { $0.documentID }

            // Batch fetch users (optimized)
            let following = try await FirestoreUserManager.shared.getUsers(userIds: followingIds)

            return following
        } catch {
            throw error
        }
    }

    // MARK: - Get Following IDs (for feed)

    func getFollowingIds(userId: String) async throws -> [String] {
        do {
            let snapshot = try await db.collection(usersCollection)
                .document(userId)
                .collection("following")
                .getDocuments()

            return snapshot.documents.map { $0.documentID }
        } catch {
            throw error
        }
    }

    // MARK: - Check Mutual Follow

    func isMutualFollow(userId: String) async throws -> Bool {
        let following = try await isFollowing(userId: userId)
        let follower = try await isFollower(userId: userId)
        return following && follower
    }

    // MARK: - Real-time Listener

    func listenToFollowers(userId: String, completion: @escaping (Result<[String], Error>) -> Void) -> ListenerRegistration {
        return db.collection(usersCollection)
            .document(userId)
            .collection("followers")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }

                let followerIds = snapshot.documents.map { $0.documentID }
                completion(.success(followerIds))
            }
    }

    func listenToFollowing(userId: String, completion: @escaping (Result<[String], Error>) -> Void) -> ListenerRegistration {
        return db.collection(usersCollection)
            .document(userId)
            .collection("following")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }

                let followingIds = snapshot.documents.map { $0.documentID }
                completion(.success(followingIds))
            }
    }
}
