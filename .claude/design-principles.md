# SugarBeat Design Principles

## Database Design Philosophy

### 正規化 vs 非正規化の判断基準

#### 基本原則：更新頻度とアクセスパターンで判断する

**正規化すべきデータ（Normalized Data）**

頻繁に更新されるデータ、または更新時に一貫性を保つ必要があるデータ：

1. **ユーザー情報**
   - ❌ 非正規化してはいけない: `username`, `displayName`, `profileImageUrl`
   - ✅ 正規化する: `userId`のみを保存し、表示時に動的に取得
   - 理由: ユーザーがプロフィールを更新したら、全ての投稿・チャンネルに反映されるべき

2. **チャンネル情報**
   - ❌ 非正規化してはいけない: `channelName`, `followerCount`, チャンネル作成者の情報
   - ✅ 正規化する: `channelId`のみを保存し、表示時に動的に取得
   - 理由: チャンネル名変更時に全ての投稿を更新するのは非効率

3. **カウント系データ**
   - ❌ 非正規化してはいけない: `likeCount`, `commentCount`, `followerCount`
   - ✅ 正規化する: サブコレクションで管理し、動的に集計
   - 理由: カウンターの同期ずれを防ぎ、削除時も自然に減る

**非正規化しても良いデータ（Denormalized Data）**

一度作成されたら変わらないデータ、または変わっても過去のデータは保持すべきもの：

1. **音楽コンテンツ情報**
   - ✅ 非正規化OK: `trackName`, `artistName`, `albumName`, `artworkUrl`, `previewUrl`
   - 理由: Apple Musicの曲情報は変わらない。変わったとしても、投稿時点の情報を保持すべき

2. **YouTube/Webサイト情報**
   - ✅ 非正規化OK: `youtubeVideoId`, `youtubeThumbnailUrl`, `websiteUrl`, `websiteTitle`
   - 理由: 投稿時点のスナップショットを保持

### Firestore Collection Structure

```
users/{userId}
  ├─ following/{followingUserId}
  ├─ followers/{followerUserId}
  └─ followingChannels/{channelId}

channels/{channelId}
  ├─ userId (owner)
  ├─ name
  ├─ latestPostId
  └─ latestPostAt

channelFollows/{channelId}
  └─ followers/{userId}

posts/{postId}
  ├─ userId
  ├─ channelId
  ├─ trackName (denormalized - OK)
  ├─ artistName (denormalized - OK)
  └─ artworkUrl (denormalized - OK)

likes/{postId}
  └─ users/{userId}

comments/{postId}
  └─ comments/{commentId}

blocks/{userId}
  └─ blockedUsers/{blockedUserId}

reports/{reportId}
```

### Model Design

#### Channel Model
```swift
struct Channel: Codable, Identifiable {
    let id: String?
    let userId: String  // ✅ Only store ID
    var name: String
    var latestPostId: String?
    var latestPostAt: Date?
    var latestPostArtworkUrl: String?

    // Computed properties (not stored in Firestore)
    var isFollowing: Bool? = nil
    var followerCount: Int? = nil  // Fetched from channelFollows/{channelId}/followers
}
```

**❌ Bad (denormalized user data)**:
```swift
let username: String
let userDisplayName: String
let userProfileImageUrl: String?
let followerCount: Int  // Stored directly
```

#### Post Model
```swift
struct Post: Codable, Identifiable {
    let id: String?
    let userId: String  // ✅ Only store ID
    let channelId: String?  // ✅ Only store ID

    // Music content (denormalized - OK because it doesn't change)
    let trackName: String?
    let artistName: String?
    let artworkUrl: String?

    // Computed properties (not stored in Firestore)
    var likeCount: Int = 0  // Fetched from likes/{postId}/users
    var commentCount: Int = 0  // Fetched from comments/{postId}/comments
}
```

**❌ Bad (denormalized mutable data)**:
```swift
let username: String
let userDisplayName: String
let userProfileImageUrl: String?
let channelName: String?
let likeCount: Int  // Stored directly
let commentCount: Int  // Stored directly
```

### Client-Side Caching Strategy

カウント系データはクライアント側でキャッシュしてパフォーマンスを向上：

1. **LikeStateManager**
   - サーバーから取得した`likeCount`をキャッシュ
   - ユーザーがいいねすると楽観的更新（Optimistic Update）
   - エラー時はロールバック

2. **CommentStateManager**
   - サーバーから取得した`commentCount`をキャッシュ
   - コメント追加時に即座に反映

3. **ViewModelでの動的取得**
   - チャンネル表示時: `channel.userId`から`User`を取得
   - 投稿表示時: `post.userId`から`User`を取得、`post.channelId`から`Channel`を取得

### Performance Optimization

**避けるべきアンチパターン:**

1. ❌ **N+1問題を起こす実装**
```swift
for post in posts {
    let user = try await getUser(userId: post.userId)  // N回のクエリ
}
```

2. ✅ **バッチフェッチで最適化**
```swift
let userIds = posts.map { $0.userId }
let users = try await getUsers(userIds: userIds)  // 1回のクエリ
```

3. ✅ **Firestoreの`in`クエリを使う（最大10件まで）**
```swift
let snapshot = try await db.collection("users")
    .whereField(FieldPath.documentID(), in: userIds)
    .getDocuments()
```

### Migration Strategy

既存の非正規化されたデータがFirestoreにある場合：

1. **後方互換性を保つ**
   - 古いフィールドは読み取り可能に保つ（CodingKeys）
   - 新しいコードでは書き込まない

2. **段階的移行**
   - Phase 1: 新しいコードをデプロイ（読み取りは古いフィールドもサポート）
   - Phase 2: Cloud Functionで既存データをクリーンアップ
   - Phase 3: 古いフィールドのサポートを削除

### Summary

- ✅ **正規化する**: `userId`, `channelId`, カウント系データ
- ✅ **非正規化OK**: 変更されない音楽/メディア情報
- ✅ **クライアントキャッシュ**: パフォーマンスのためカウントはキャッシュ
- ✅ **バッチフェッチ**: N+1問題を避ける
- ❌ **非正規化NG**: ユーザー情報、チャンネル名、カウンターなど変更される可能性があるデータ

この設計により、データの一貫性を保ちながら、パフォーマンスも最適化できます。
