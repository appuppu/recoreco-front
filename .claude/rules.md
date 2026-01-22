# Development Rules

## General Principles

### 1. No Quick Fixes - 時間をかけて正しい実装をする

**❌ 避けるべき行動：**
- その場しのぎの解決
- 一時的な回避策（temporary workaround）
- 技術的負債を増やす変更
- 「とりあえず動けばいい」という発想

**✅ 推奨される行動：**
- 根本原因を特定して解決する
- 設計原則に従った実装
- 長期的なメンテナンス性を考慮する
- 時間がかかっても正しい方法を選ぶ

**例：**
```swift
// ❌ Bad: その場しのぎ
// フィールドが存在しない問題に対して、オプショナルで回避
var username: String? = post.username ?? "Unknown"

// ✅ Good: 根本的な解決
// userIdから動的にユーザー情報を取得するように設計変更
let user = try await FirestoreUserManager.shared.getUser(userId: post.userId)
let username = user.username
```

### 2. Follow Design Principles - 設計原則に従う

**データベース設計:**
- 非正規化は慎重に判断する（design-principles.mdを参照）
- 更新が頻繁なデータは正規化する
- データの一貫性を最優先する

**コード設計:**
- SOLID原則に従う
- 責任の分離（Separation of Concerns）
- DRY（Don't Repeat Yourself）

### 3. Prioritize Code Quality - コード品質を優先する

**コードレビューの観点:**
- 読みやすさ
- テスタビリティ
- パフォーマンス
- セキュリティ

**リファクタリング:**
- 定期的にコードベースを見直す
- 技術的負債を放置しない
- 改善の機会を見逃さない

### 4. Think Long-term - 長期的視点を持つ

**質問すべきこと:**
- この変更は1年後も保守できるか？
- 新しい機能を追加する際に障害にならないか？
- チームメンバーが理解できるコードか？
- スケールする設計か？

**避けるべき短期的思考:**
- 「今だけ動けば良い」
- 「後で直す」（実際には直さない）
- 「誰も見ないから」
- 「締め切りが迫っているから」

### 5. Document Decisions - 意思決定を記録する

**ドキュメント化すべきこと:**
- 設計判断の理由
- トレードオフの考慮
- 代替案とその却下理由
- アーキテクチャの変更履歴

**場所:**
- `.claude/design-principles.md` - 設計原則
- `.claude/architecture.md` - アーキテクチャ決定
- コード内コメント - 複雑なロジックの説明

### 6. Test Thoroughly - 徹底的にテストする

**テスト戦略:**
- ユニットテスト
- インテグレーションテスト
- エンドツーエンドテスト
- エッジケースのテスト

**テスト前の確認:**
- すべての変更箇所を網羅しているか？
- リグレッションがないか？
- パフォーマンスに影響はないか？

## Specific to SugarBeat

### Database Design

1. **NO Denormalization of Mutable Data**
   - ユーザー情報（username, displayName, profileImageUrl）は非正規化しない
   - チャンネル情報（channelName, followerCount）は非正規化しない
   - カウント系データ（likeCount, commentCount）は非正規化しない

2. **Use References, Not Copies**
   - `userId`を保存、`username`は保存しない
   - `channelId`を保存、`channelName`は保存しない
   - サブコレクションでカウントを管理

3. **Dynamic Fetching**
   - 表示時にuserIdからユーザー情報を取得
   - 表示時にchannelIdからチャンネル情報を取得
   - サブコレクションから動的にカウント

### Performance Optimization

1. **Batch Fetching**
   - N+1クエリを避ける
   - 可能な限りバッチでデータ取得

2. **Client-side Caching**
   - LikeStateManager, CommentStateManagerでキャッシュ
   - UIの応答性を保つ

3. **Optimistic Updates**
   - ユーザーアクション（いいね、コメント）は楽観的更新
   - エラー時はロールバック

## Summary

- ✅ 時間をかけて正しい実装をする
- ✅ 設計原則に従う
- ✅ コード品質を優先する
- ✅ 長期的視点を持つ
- ✅ 意思決定を記録する
- ✅ 徹底的にテストする
- ❌ その場しのぎの解決はしない
- ❌ 技術的負債を増やさない
- ❌ 短期的思考で妥協しない
