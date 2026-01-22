import Foundation
import FirebaseFirestore

/// In-memory cache manager to reduce Firestore reads
class FirestoreCacheManager {
    static let shared = FirestoreCacheManager()

    private var userCache: [String: CacheItem<User>] = [:]
    private var postCache: [String: CacheItem<Post>] = [:]

    private let cacheQueue = DispatchQueue(label: "com.sugarbeat.cache", attributes: .concurrent)

    // Cache duration in seconds
    private let userCacheDuration: TimeInterval = 300 // 5 minutes
    private let postCacheDuration: TimeInterval = 60  // 1 minute

    private init() {}

    // MARK: - Cache Item

    private struct CacheItem<T> {
        let data: T
        let timestamp: Date

        func isValid(duration: TimeInterval) -> Bool {
            return Date().timeIntervalSince(timestamp) < duration
        }
    }

    // MARK: - User Cache

    func cacheUser(_ user: User) {
        guard let userId = user.id else { return }
        cacheQueue.async(flags: .barrier) {
            self.userCache[userId] = CacheItem(data: user, timestamp: Date())
        }
    }

    func getCachedUser(userId: String) -> User? {
        var cachedItem: CacheItem<User>?
        cacheQueue.sync {
            cachedItem = userCache[userId]
        }

        if let item = cachedItem, item.isValid(duration: userCacheDuration) {
            return item.data
        }

        return nil
    }

    func cacheUsers(_ users: [User]) {
        cacheQueue.async(flags: .barrier) {
            for user in users {
                guard let userId = user.id else { continue }
                self.userCache[userId] = CacheItem(data: user, timestamp: Date())
            }
        }
    }

    func invalidateUser(userId: String) {
        cacheQueue.async(flags: .barrier) {
            self.userCache.removeValue(forKey: userId)
        }
    }

    // MARK: - Post Cache

    func cachePost(_ post: Post) {
        guard let postId = post.id else { return }
        cacheQueue.async(flags: .barrier) {
            self.postCache[postId] = CacheItem(data: post, timestamp: Date())
        }
    }

    func getCachedPost(postId: String) -> Post? {
        var cachedItem: CacheItem<Post>?
        cacheQueue.sync {
            cachedItem = postCache[postId]
        }

        if let item = cachedItem, item.isValid(duration: postCacheDuration) {
            return item.data
        }

        return nil
    }

    func cachePosts(_ posts: [Post]) {
        cacheQueue.async(flags: .barrier) {
            for post in posts {
                guard let postId = post.id else { continue }
                self.postCache[postId] = CacheItem(data: post, timestamp: Date())
            }
        }
    }

    func invalidatePost(postId: String) {
        cacheQueue.async(flags: .barrier) {
            self.postCache.removeValue(forKey: postId)
        }
    }

    // MARK: - Clear Cache

    func clearUserCache() {
        cacheQueue.async(flags: .barrier) {
            self.userCache.removeAll()
        }
    }

    func clearPostCache() {
        cacheQueue.async(flags: .barrier) {
            self.postCache.removeAll()
        }
    }

    func clearAllCache() {
        cacheQueue.async(flags: .barrier) {
            self.userCache.removeAll()
            self.postCache.removeAll()
        }
    }

    // MARK: - Cache Stats (for debugging)

    func getCacheStats() -> (userCount: Int, postCount: Int) {
        var stats: (Int, Int) = (0, 0)
        cacheQueue.sync {
            stats = (userCache.count, postCache.count)
        }
        return stats
    }
}
