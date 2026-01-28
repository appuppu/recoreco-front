import Foundation
import FirebaseFirestore

/// In-memory cache manager to reduce Firestore reads
class FirestoreCacheManager {
    static let shared = FirestoreCacheManager()

    private var userCache: [String: CacheItem<User>] = [:]
    private var postCache: [String: CacheItem<Post>] = [:]
    private var channelCache: [String: CacheItem<Channel>] = [:]
    private var userChannelsCache: [String: CacheItem<[Channel]>] = [:] // userId -> channels list
    private var followedChannelsCache: [String: CacheItem<[Channel]>] = [:] // userId -> followed channels list

    private let cacheQueue = DispatchQueue(label: "com.sugarbeat.cache", attributes: .concurrent)

    // Cache duration in seconds
    private let userCacheDuration: TimeInterval = 300 // 5 minutes
    private let postCacheDuration: TimeInterval = 60  // 1 minute
    private let channelCacheDuration: TimeInterval = 300 // 5 minutes
    private let channelListCacheDuration: TimeInterval = 60 // 1 minute for channel lists

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

    // MARK: - Channel Cache

    func cacheChannel(_ channel: Channel) {
        guard let channelId = channel.id else { return }
        cacheQueue.async(flags: .barrier) {
            self.channelCache[channelId] = CacheItem(data: channel, timestamp: Date())
        }
    }

    func getCachedChannel(channelId: String) -> Channel? {
        var cachedItem: CacheItem<Channel>?
        cacheQueue.sync {
            cachedItem = channelCache[channelId]
        }

        if let item = cachedItem, item.isValid(duration: channelCacheDuration) {
            return item.data
        }

        return nil
    }

    func cacheChannels(_ channels: [Channel]) {
        cacheQueue.async(flags: .barrier) {
            for channel in channels {
                guard let channelId = channel.id else { continue }
                self.channelCache[channelId] = CacheItem(data: channel, timestamp: Date())
            }
        }
    }

    func invalidateChannel(channelId: String) {
        cacheQueue.async(flags: .barrier) {
            self.channelCache.removeValue(forKey: channelId)
        }
    }

    // MARK: - Channel List Cache

    func cacheUserChannels(userId: String, channels: [Channel]) {
        cacheQueue.async(flags: .barrier) {
            self.userChannelsCache[userId] = CacheItem(data: channels, timestamp: Date())
        }
        // Also cache individual channels
        cacheChannels(channels)
    }

    func getCachedUserChannels(userId: String) -> [Channel]? {
        var cachedItem: CacheItem<[Channel]>?
        cacheQueue.sync {
            cachedItem = userChannelsCache[userId]
        }

        if let item = cachedItem, item.isValid(duration: channelListCacheDuration) {
            return item.data
        }

        return nil
    }

    func cacheFollowedChannels(userId: String, channels: [Channel]) {
        cacheQueue.async(flags: .barrier) {
            self.followedChannelsCache[userId] = CacheItem(data: channels, timestamp: Date())
        }
        // Also cache individual channels
        cacheChannels(channels)
    }

    func getCachedFollowedChannels(userId: String) -> [Channel]? {
        var cachedItem: CacheItem<[Channel]>?
        cacheQueue.sync {
            cachedItem = followedChannelsCache[userId]
        }

        if let item = cachedItem, item.isValid(duration: channelListCacheDuration) {
            return item.data
        }

        return nil
    }

    func invalidateUserChannels(userId: String) {
        cacheQueue.async(flags: .barrier) {
            self.userChannelsCache.removeValue(forKey: userId)
            self.followedChannelsCache.removeValue(forKey: userId)
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

    func clearChannelCache() {
        cacheQueue.async(flags: .barrier) {
            self.channelCache.removeAll()
            self.userChannelsCache.removeAll()
            self.followedChannelsCache.removeAll()
        }
    }

    func clearAllCache() {
        cacheQueue.async(flags: .barrier) {
            self.userCache.removeAll()
            self.postCache.removeAll()
            self.channelCache.removeAll()
            self.userChannelsCache.removeAll()
            self.followedChannelsCache.removeAll()
        }
    }

    // MARK: - Cache Stats (for debugging)

    func getCacheStats() -> (userCount: Int, postCount: Int, channelCount: Int, channelListCount: Int) {
        var stats: (Int, Int, Int, Int) = (0, 0, 0, 0)
        cacheQueue.sync {
            stats = (userCache.count, postCache.count, channelCache.count, userChannelsCache.count + followedChannelsCache.count)
        }
        return stats
    }
}
