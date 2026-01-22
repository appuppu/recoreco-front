import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirestoreReportManager {
    static let shared = FirestoreReportManager()
    private let db = Firestore.firestore()
    private let reportsCollection = "reports"

    private init() {}

    // MARK: - Report Post

    func reportPost(postId: String, reason: String, description: String?) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        let report = Report(
            reporterId: currentUserId,
            type: .post,
            targetId: postId,
            reason: reason,
            description: description
        )

        do {
            let _ = try db.collection(reportsCollection).addDocument(from: report)
            print("✅ Post reported: \(postId)")
        } catch {
            throw error
        }
    }

    // MARK: - Report Comment

    func reportComment(commentId: String, reason: String, description: String?) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        let report = Report(
            reporterId: currentUserId,
            type: .comment,
            targetId: commentId,
            reason: reason,
            description: description
        )

        do {
            let _ = try db.collection(reportsCollection).addDocument(from: report)
            print("✅ Comment reported: \(commentId)")
        } catch {
            throw error
        }
    }

    // MARK: - Report Channel

    func reportChannel(channelId: String, reason: String, description: String?) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw FirestoreUserError.notAuthenticated
        }

        let report = Report(
            reporterId: currentUserId,
            type: .channel,
            targetId: channelId,
            reason: reason,
            description: description
        )

        do {
            let _ = try db.collection(reportsCollection).addDocument(from: report)
            print("✅ Channel reported: \(channelId)")
        } catch {
            throw error
        }
    }

    // MARK: - Get Reports (Admin only - not used in client app)

    func getReports(limit: Int = 50, lastDocument: DocumentSnapshot? = nil) async throws -> ([Report], DocumentSnapshot?) {
        do {
            var query = db.collection(reportsCollection)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)

            if let lastDocument = lastDocument {
                query = query.start(afterDocument: lastDocument)
            }

            let snapshot = try await query.getDocuments()
            let reports = try snapshot.documents.compactMap { try $0.data(as: Report.self) }

            let lastDoc = snapshot.documents.last
            return (reports, lastDoc)
        } catch {
            throw error
        }
    }

    // MARK: - Check if User Already Reported

    func hasUserReportedPost(postId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        do {
            let snapshot = try await db.collection(reportsCollection)
                .whereField("reporterId", isEqualTo: currentUserId)
                .whereField("type", isEqualTo: Report.ReportType.post.rawValue)
                .whereField("targetId", isEqualTo: postId)
                .limit(to: 1)
                .getDocuments()

            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }

    func hasUserReportedComment(commentId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        do {
            let snapshot = try await db.collection(reportsCollection)
                .whereField("reporterId", isEqualTo: currentUserId)
                .whereField("type", isEqualTo: Report.ReportType.comment.rawValue)
                .whereField("targetId", isEqualTo: commentId)
                .limit(to: 1)
                .getDocuments()

            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }

    func hasUserReportedChannel(channelId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }

        do {
            let snapshot = try await db.collection(reportsCollection)
                .whereField("reporterId", isEqualTo: currentUserId)
                .whereField("type", isEqualTo: Report.ReportType.channel.rawValue)
                .whereField("targetId", isEqualTo: channelId)
                .limit(to: 1)
                .getDocuments()

            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }
}
