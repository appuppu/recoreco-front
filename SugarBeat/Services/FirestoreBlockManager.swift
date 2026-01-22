import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreBlockManager {
    static let shared = FirestoreBlockManager()
    private let db = Firestore.firestore()
    private let blocksCollection = "blocks"

    private init() {}

    // MARK: - Block User

    func blockUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        guard currentUserId != userId else {
            return // Cannot block yourself
        }

        let blockId = "\(currentUserId)_\(userId)"

        let blockData: [String: Any] = [
            "blockerId": currentUserId,
            "blockedId": userId,
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection(blocksCollection).document(blockId).setData(blockData)
            print("✅ Blocked user: \(userId)")

            // Optionally: Remove follow relationships
            try? await FirestoreFollowManager.shared.unfollowUser(userId: userId)

            // Post notification that user was blocked
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Foundation.Notification.Name.userBlocked,
                    object: nil,
                    userInfo: ["blockedUserId": userId]
                )
            }
        } catch {
            throw error
        }
    }

    // MARK: - Unblock User

    func unblockUser(userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        let blockId = "\(currentUserId)_\(userId)"

        do {
            try await db.collection(blocksCollection).document(blockId).delete()
            print("✅ Unblocked user: \(userId)")
        } catch {
            throw error
        }
    }

    // MARK: - Check Block Status

    func isUserBlocked(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        guard currentUserId != userId else {
            return false
        }

        let blockId = "\(currentUserId)_\(userId)"

        do {
            let document = try await db.collection(blocksCollection).document(blockId).getDocument()
            return document.exists
        } catch {
            return false
        }
    }

    func isBlockedBy(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        guard currentUserId != userId else {
            return false
        }

        let blockId = "\(userId)_\(currentUserId)"

        do {
            let document = try await db.collection(blocksCollection).document(blockId).getDocument()
            return document.exists
        } catch {
            return false
        }
    }

    // MARK: - Get Blocked Users

    func getBlockedUsers() async throws -> [String] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        do {
            let snapshot = try await db.collection(blocksCollection)
                .whereField("blockerId", isEqualTo: currentUserId)
                .getDocuments()

            let blockedIds = snapshot.documents.compactMap { doc -> String? in
                return doc.data()["blockedId"] as? String
            }

            return blockedIds
        } catch {
            throw error
        }
    }

    // MARK: - Get Users Who Blocked Current User

    func getUsersWhoBlockedMe() async throws -> [String] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        do {
            let snapshot = try await db.collection(blocksCollection)
                .whereField("blockedId", isEqualTo: currentUserId)
                .getDocuments()

            let blockerIds = snapshot.documents.compactMap { doc -> String? in
                return doc.data()["blockerId"] as? String
            }

            return blockerIds
        } catch {
            throw error
        }
    }

    // MARK: - Get All Block-Related Users (both blocked and blockers)

    func getAllBlockRelatedUsers() async throws -> [String] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        do {
            // Get users I blocked
            let blockedByMe = try await getBlockedUsers()

            // Get users who blocked me
            let blockedMe = try await getUsersWhoBlockedMe()

            // Combine both sets
            let allBlockedUsers = Set(blockedByMe).union(Set(blockedMe))

            return Array(allBlockedUsers)
        } catch {
            throw error
        }
    }

    func getBlockedUsersDetails() async throws -> [User] {
        let blockedIds = try await getBlockedUsers()

        var blockedUsers: [User] = []
        for userId in blockedIds {
            if let user = try? await FirestoreUserManager.shared.getUser(userId: userId) {
                blockedUsers.append(user)
            }
        }

        return blockedUsers
    }

    // MARK: - Real-time Listener

    func listenToBlockedUsers(completion: @escaping (Result<[String], Error>) -> Void) -> ListenerRegistration? {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return nil
        }

        return db.collection(blocksCollection)
            .whereField("blockerId", isEqualTo: currentUserId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot = snapshot else {
                    completion(.success([]))
                    return
                }

                let blockedIds = snapshot.documents.compactMap { doc -> String? in
                    return doc.data()["blockedId"] as? String
                }

                completion(.success(blockedIds))
            }
    }
}
