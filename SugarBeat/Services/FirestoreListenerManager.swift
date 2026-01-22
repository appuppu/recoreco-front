import Foundation
import FirebaseFirestore

/// Manages Firestore listeners to prevent memory leaks and reduce costs
class FirestoreListenerManager {
    static let shared = FirestoreListenerManager()

    private var listeners: [String: ListenerRegistration] = [:]
    private let queue = DispatchQueue(label: "com.sugarbeat.listeners", attributes: .concurrent)

    private init() {}

    // MARK: - Add Listener

    func addListener(key: String, listener: ListenerRegistration) {
        queue.async(flags: .barrier) {
            // Remove existing listener if any
            self.listeners[key]?.remove()
            self.listeners[key] = listener
        }
        print("📡 Added listener: \(key)")
    }

    // MARK: - Remove Listener

    func removeListener(key: String) {
        queue.async(flags: .barrier) {
            self.listeners[key]?.remove()
            self.listeners.removeValue(forKey: key)
        }
        print("📡 Removed listener: \(key)")
    }

    // MARK: - Remove All Listeners

    func removeAllListeners() {
        queue.async(flags: .barrier) {
            for listener in self.listeners.values {
                listener.remove()
            }
            self.listeners.removeAll()
        }
        print("📡 Removed all listeners")
    }

    // MARK: - Remove Listeners by Prefix

    func removeListeners(withPrefix prefix: String) {
        queue.async(flags: .barrier) {
            let keysToRemove = self.listeners.keys.filter { $0.hasPrefix(prefix) }
            for key in keysToRemove {
                self.listeners[key]?.remove()
                self.listeners.removeValue(forKey: key)
            }
        }
        print("📡 Removed listeners with prefix: \(prefix)")
    }

    // MARK: - Get Active Listener Count

    func getActiveListenerCount() -> Int {
        var count = 0
        queue.sync {
            count = listeners.count
        }
        return count
    }

    // MARK: - Check if Listener Exists

    func hasListener(key: String) -> Bool {
        var exists = false
        queue.sync {
            exists = listeners[key] != nil
        }
        return exists
    }
}

// MARK: - Listener Key Helper

extension FirestoreListenerManager {
    /// Generate listener keys for consistent management
    enum ListenerKey {
        static func post(postId: String) -> String {
            return "post_\(postId)"
        }

        static func userPosts(userId: String) -> String {
            return "userPosts_\(userId)"
        }

        static func notifications(userId: String) -> String {
            return "notifications_\(userId)"
        }

        static func unreadCount(userId: String) -> String {
            return "unreadCount_\(userId)"
        }

        static func comments(postId: String) -> String {
            return "comments_\(postId)"
        }

        static func likes(postId: String) -> String {
            return "likes_\(postId)"
        }

        static func followers(userId: String) -> String {
            return "followers_\(userId)"
        }

        static func following(userId: String) -> String {
            return "following_\(userId)"
        }

        static func user(userId: String) -> String {
            return "user_\(userId)"
        }

        static func feed() -> String {
            return "feed"
        }
    }
}
