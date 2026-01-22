# Firebase移行 - 次のステップ

## 完了した作業 ✅

### 1. Firebase基盤
- ✅ Podfileの更新（Firestore, Storage, Messaging追加）
- ✅ FirebaseConfig.swift作成（開発/本番環境切り替え）
- ✅ 認証機能（Google, Apple Sign-In）実装

### 2. データモデル
- ✅ User モデル（Firestore対応）
- ✅ Post モデル（Firestore対応）
- ✅ Comment モデル（Firestore対応）
- ✅ Notification モデル（Firestore対応）

### 3. Managerクラス
- ✅ FirebaseStorageManager - 画像アップロード/削除
- ✅ FirestoreUserManager - ユーザーCRUD、検索
- ✅ FirestorePostManager - 投稿CRUD、フィード取得
- ✅ FirestoreFollowManager - フォロー/アンフォロー
- ✅ FirestoreLikeManager - いいね/いいね解除
- ✅ FirestoreCommentManager - コメントCRUD
- ✅ FirestoreNotificationManager - 通知管理
- ✅ FirestoreBlockManager - ブロック管理
- ✅ AuthManager - Firestore連携

## 今後必要な作業 🚧

### Phase 1: 環境セットアップ（今すぐ実行）

#### 1. 依存関係のインストール
```bash
cd /Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front
pod install
```

#### 2. Firebase Console設定
1. 開発環境プロジェクト作成
   - プロジェクト名: `sugarbeat-dev`
   - iOS Bundle ID: あなたのBundle ID + `.dev`
   - `GoogleService-Info-Dev.plist` をダウンロード

2. 本番環境プロジェクト作成
   - プロジェクト名: `sugarbeat-prod`
   - iOS Bundle ID: あなたのBundle ID
   - `GoogleService-Info-Prod.plist` をダウンロード

3. 両方のplistファイルをXcodeプロジェクトに追加

#### 3. Firebase Authentication有効化
- Google Sign-In を有効化
- Apple Sign-In を有効化

#### 4. Firestore Database作成
- Firebase Console → Firestore Database
- 「Create Database」をクリック
- テストモードで開始（後でRulesを設定）

#### 5. Firebase Storage有効化
- Firebase Console → Storage
- 「Get Started」をクリック
- テストモードで開始（後でRulesを設定）

#### 6. Security Rules設定
`FIREBASE_MIGRATION.md` に記載されているRulesをコピーして設定

### Phase 2: ViewModelの移行

現在のViewModelはAPIClientを使用しているため、Firestore Managerを使用するように書き換えが必要です。

#### 優先順位の高いViewModel:
1. **FeedViewModel** → FirestorePostManager
2. **CreatePostViewModel** → FirestorePostManager, FirebaseStorageManager
3. **UserProfileViewModel** → FirestoreUserManager, FirestoreFollowManager
4. **NotificationsViewModel** → FirestoreNotificationManager
5. **SearchViewModel** → FirestoreUserManager

#### 移行方法の例（FeedViewModel）:

**現在:**
```swift
let posts = try await APIClient.shared.getDiscoveryFeed()
```

**変更後:**
```swift
let (posts, lastDoc) = try await FirestorePostManager.shared.getDiscoveryFeed(limit: 20)
```

### Phase 3: リアルタイム機能の実装

Firestoreのリアルタイムリスナーを活用:

1. **通知のリアルタイム更新**
```swift
let listener = FirestoreNotificationManager.shared.listenToNotifications(userId: currentUserId) { result in
    // 通知を更新
}
```

2. **いいね数のリアルタイム更新**
```swift
let listener = FirestoreLikeManager.shared.listenToPostLikes(postId: postId) { result in
    // いいね数を更新
}
```

3. **コメントのリアルタイム更新**
```swift
let listener = FirestoreCommentManager.shared.listenToComments(postId: postId) { result in
    // コメント一覧を更新
}
```

### Phase 4: 画像アップロードの移行

**現在:**
```swift
let imageUrl = try await APIClient.shared.uploadImage(imageData: data)
```

**変更後:**
```swift
let imageUrl = try await FirebaseStorageManager.shared.uploadProfileImage(image, userId: userId)
```

### Phase 5: エラーハンドリングとログ

Firebaseエラーを適切にハンドリング:
```swift
do {
    try await FirestorePostManager.shared.createPost(post)
} catch FirestorePostError.createFailed(let error) {
    print("投稿作成失敗: \(error)")
} catch {
    print("予期しないエラー: \(error)")
}
```

### Phase 6: オフライン対応

Firestoreのオフラインキャッシュを有効化（すでに設定済み）:
```swift
let settings = FirestoreSettings()
settings.cacheSettings = MemoryCacheSettings()
db.settings = settings
```

### Phase 7: パフォーマンス最適化

1. **Composite Index作成**
   - Firebase Console → Firestore → Indexes
   - アプリ実行時にエラーが出たら、エラーメッセージのリンクからIndexを作成

2. **ページネーション実装**
   - `lastDocument` を使用して次のページを取得
   - 無限スクロールの実装

3. **Denormalization（非正規化）の活用**
   - すでに実装済み（Postにユーザー情報を含める）

## テスト手順

### 1. 認証テスト
- [ ] メールアドレスでサインアップ
- [ ] メールアドレスでログイン
- [ ] Googleでログイン
- [ ] Appleでログイン
- [ ] ログアウト

### 2. 投稿テスト
- [ ] 投稿作成
- [ ] 投稿一覧表示
- [ ] 投稿詳細表示
- [ ] 投稿削除

### 3. いいねテスト
- [ ] いいね
- [ ] いいね解除
- [ ] いいね数表示

### 4. コメントテスト
- [ ] コメント作成
- [ ] コメント一覧表示
- [ ] コメント削除

### 5. フォローテスト
- [ ] フォロー
- [ ] アンフォロー
- [ ] フォロワー一覧
- [ ] フォロー中一覧

### 6. 通知テスト
- [ ] いいね通知
- [ ] コメント通知
- [ ] フォロー通知
- [ ] 通知削除

### 7. 検索テスト
- [ ] ユーザー検索
- [ ] ユーザー名で検索
- [ ] 表示名で検索

## 重要な注意事項

### 1. AuthResponse型の不一致

現在の`AuthResponse`は`userId: Int64`を使用していますが、FirebaseのUIDは`String`です。

**対応方法:**
- バックエンドでFirebase UIDを返すように変更
- または、AuthManagerで変換処理を追加

### 2. APIClientとの並行運用

完全移行まではAPIClientとFirebase Managerを並行して使用する必要があります。

**推奨:**
- 新機能はFirebaseで実装
- 既存機能は段階的に移行

### 3. セキュリティルール

テストモードのRulesは**全てのデータへのアクセスを許可**します。必ず本番環境用のRulesを設定してください。

### 4. コスト管理

Firestoreは読み取り/書き込み回数で課金されます:
- 不要な読み取りを避ける
- リスナーを適切に解除する
- キャッシュを活用する

## トラブルシューティング

### ビルドエラー
```bash
# Podを再インストール
pod deintegrate
pod install

# Xcodeをクリーン
# Cmd + Shift + K
```

### Firestore接続エラー
- GoogleService-Info.plist が正しく配置されているか確認
- Firebase Console でプロジェクトが有効化されているか確認
- Bundle ID が一致しているか確認

### 認証エラー
- Firebase Console → Authentication で認証方法が有効化されているか確認
- Google Sign-In の場合: REVERSED_CLIENT_ID が設定されているか確認
- Apple Sign-In の場合: Capability が追加されているか確認

## 参考ドキュメント

- `FIREBASE_MIGRATION.md` - 詳細な移行プラン
- `FIREBASE_SETUP.md` - Firebase初期セットアップ手順
- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Firebase Storage Documentation](https://firebase.google.com/docs/storage)

## 質問・サポート

Firebase移行で困ったことがあれば、以下を確認してください:
1. エラーメッセージを確認
2. Firebase Console でログを確認
3. ドキュメントを確認
4. Stack Overflow で検索
