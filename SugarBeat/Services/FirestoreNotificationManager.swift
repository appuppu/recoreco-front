import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreNotificationManager {
    static let shared = FirestoreNotificationManager()
    private let db = Firestore.firestore()
    private let notificationsCollection = "notifications"

    private init() {}

    // MARK: - Create Notification

    func createNotification(_ notification: Notification) async throws {
        do {
            let _ = try db.collection(notificationsCollection).addDocument(from: notification)
            print("✅ Notification created for user: \(notification.recipientId)")
        } catch {
            throw error
        }
    }

    // MARK: - Get Notifications

    func getNotifications(userId: String, limit: Int = 50, lastDocument: DocumentSnapshot? = nil) async throws -> ([Notification], DocumentSnapshot?) {
        do {
            var query = db.collection(notificationsCollection)
                .whereField("recipientId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            let notifications = try snapshot.documents.compactMap { try $0.data(as: Notification.self) }

            let lastDoc = snapshot.documents.last
            return (notifications, lastDoc)
        } catch {
            throw error
        }
    }

    func getCurrentUserNotifications(limit: Int = 50, lastDocument: DocumentSnapshot? = nil) async throws -> ([Notification], DocumentSnapshot?) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        return try await getNotifications(userId: currentUserId, limit: limit, lastDocument: lastDocument)
    }

    // MARK: - Mark as Read

    func markAsRead(notificationId: String) async throws {
        try await db.collection(notificationsCollection).document(notificationId).updateData([
            "isRead": true
        ])
        print("✅ Notification marked as read: \(notificationId)")
    }

    func markAllAsRead(userId: String) async throws {
        let snapshot = try await db.collection(notificationsCollection)
            .whereField("recipientId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        let batch = db.batch()

        for document in snapshot.documents {
            batch.updateData(["isRead": true], forDocument: document.reference)
        }

        try await batch.commit()
        print("✅ All notifications marked as read for user: \(userId)")
    }

    // MARK: - Delete Notification

    func deleteNotification(notificationId: String) async throws {
        try await db.collection(notificationsCollection).document(notificationId).delete()
        print("✅ Notification deleted: \(notificationId)")
    }

    func deleteAllNotifications(userId: String) async throws {
        let snapshot = try await db.collection(notificationsCollection)
            .whereField("recipientId", isEqualTo: userId)
            .getDocuments()

        let batch = db.batch()

        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }

        try await batch.commit()
        print("✅ All notifications deleted for user: \(userId)")
    }

    // MARK: - Get Unread Count

    func getUnreadCount(userId: String) async throws -> Int {
        let snapshot = try await db.collection(notificationsCollection)
            .whereField("recipientId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        return snapshot.documents.count
    }

    func getCurrentUserUnreadCount() async throws -> Int {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return 0
        }

        return try await getUnreadCount(userId: currentUserId)
    }

    // MARK: - Real-time Listener

    func listenToNotifications(userId: String, completion: @escaping (Result<[Notification], Error>) -> Void) -> ListenerRegistration {
        return db.collection(notificationsCollection)
            .whereField("recipientId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
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
                    let notifications = try snapshot.documents.compactMap { try $0.data(as: Notification.self) }
                    completion(.success(notifications))
                } catch {
                    completion(.failure(error))
                }
            }
    }

    func listenToUnreadCount(userId: String, completion: @escaping (Result<Int, Error>) -> Void) -> ListenerRegistration {
        return db.collection(notificationsCollection)
            .whereField("recipientId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
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
