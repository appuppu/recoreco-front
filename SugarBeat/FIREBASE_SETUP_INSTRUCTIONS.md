# Firebase セットアップ手順書 🔥

このドキュメントでは、FirebaseコンソールでRulesとIndexesを設定する手順を説明します。

## 📋 目次

1. [Firestore Security Rules の設定](#1-firestore-security-rules-の設定)
2. [Storage Security Rules の設定](#2-storage-security-rules-の設定)
3. [Firestore Indexes の設定](#3-firestore-indexes-の設定)
4. [動作確認](#4-動作確認)

---

## 1. Firestore Security Rules の設定

### 手順

1. **Firebase Console を開く**
   - https://console.firebase.google.com/
   - プロジェクトを選択（開発環境と本番環境の両方で実施）

2. **Firestore Database に移動**
   - 左メニュー → 「Firestore Database」
   - 上部タブ → 「ルール」をクリック

3. **ルールをコピペ**
   - `firebase/firestore.rules` の内容を**全てコピー**
   - Firebaseコンソールのエディタに**全て貼り付け**（既存の内容を削除して置き換え）

4. **公開**
   - 「公開」ボタンをクリック
   - 確認ダイアログで「公開」を選択

### ⚠️ 重要な注意事項

#### テストモードとの違い
```javascript
// ❌ テストモード（開発中のみ使用）
allow read, write: if true;  // 誰でもアクセス可能（危険）

// ✅ 本番用ルール
allow read: if isAuthenticated();  // 認証済みユーザーのみ
allow write: if isOwner(userId);   // 所有者のみ
```

#### ルールの確認
エディタの下部に「シミュレータ」があります。以下をテスト：

```
テスト1: 未認証ユーザーが投稿を読む
- コレクション: posts
- ドキュメントID: test123
- 認証: なし
- 期待結果: ❌ アクセス拒否

テスト2: 認証済みユーザーが投稿を読む
- コレクション: posts
- ドキュメントID: test123
- 認証: あり (テストUID: testUser123)
- 期待結果: ✅ アクセス許可

テスト3: ユーザーが他人のプロフィールを更新
- コレクション: users
- ドキュメントID: otherUser456
- 認証: あり (テストUID: testUser123)
- 操作: update
- 期待結果: ❌ アクセス拒否

テスト4: ユーザーが自分のプロフィールを更新
- コレクション: users
- ドキュメントID: testUser123
- 認証: あり (テストUID: testUser123)
- 操作: update
- 期待結果: ✅ アクセス許可
```

---

## 2. Storage Security Rules の設定

### 手順

1. **Firebase Console を開く**
   - 同じプロジェクトで続行

2. **Storage に移動**
   - 左メニュー → 「Storage」
   - 上部タブ → 「ルール」をクリック

3. **ルールをコピペ**
   - `firebase/storage.rules` の内容を**全てコピー**
   - エディタに**全て貼り付け**（既存の内容を削除して置き換え）

4. **公開**
   - 「公開」ボタンをクリック

### ⚠️ 重要な注意事項

#### 画像サイズ制限
現在の設定では**5MB以下**の画像のみアップロード可能です。

変更する場合は以下を編集：
```javascript
function isUnder5MB() {
  return request.resource.size < 5 * 1024 * 1024;  // 5MB
}

// 10MBに変更する場合
function isUnder10MB() {
  return request.resource.size < 10 * 1024 * 1024;  // 10MB
}
```

#### 許可される画像形式
```javascript
function isImage() {
  return request.resource.contentType.matches('image/.*');
}
```

これにより以下の形式が許可されます：
- image/jpeg
- image/png
- image/gif
- image/webp
- など

---

## 3. Firestore Indexes の設定

### 方法1: Firebase Console（推奨）

#### 手順

1. **Firebase Console を開く**
   - 同じプロジェクトで続行

2. **Firestore Database に移動**
   - 左メニュー → 「Firestore Database」
   - 上部タブ → 「インデックス」をクリック

3. **複合インデックスを作成**

   以下のインデックスを1つずつ作成します：

   #### インデックス1: posts（ユーザーの投稿一覧）
   ```
   コレクションID: posts
   フィールド1: userId (昇順)
   フィールド2: createdAt (降順)
   クエリスコープ: コレクション
   ```

   #### インデックス2: notifications（通知一覧）
   ```
   コレクションID: notifications
   フィールド1: recipientId (昇順)
   フィールド2: createdAt (降順)
   クエリスコープ: コレクション
   ```

   #### インデックス3: notifications（未読通知）
   ```
   コレクションID: notifications
   フィールド1: recipientId (昇順)
   フィールド2: isRead (昇順)
   フィールド3: createdAt (降順)
   クエリスコープ: コレクション
   ```

   #### インデックス4: comments（投稿のコメント）
   ```
   コレクションID: comments
   フィールド1: postId (昇順)
   フィールド2: createdAt (昇順)
   クエリスコープ: コレクショングループ
   ```

   #### インデックス5: blocks（ブロックリスト）
   ```
   コレクションID: blocks
   フィールド1: blockerId (昇順)
   フィールド2: blockedId (昇順)
   クエリスコープ: コレクション
   ```

   #### インデックス6: reports（通報の検索）
   ```
   コレクションID: reports
   フィールド1: reporterId (昇順)
   フィールド2: type (昇順)
   フィールド3: targetId (昇順)
   クエリスコープ: コレクション
   ```

4. **作成完了を待つ**
   - インデックスの作成には数分かかることがあります
   - ステータスが「作成中」→「有効」になるのを待ちます

### 方法2: Firebase CLI（上級者向け）

#### 前提条件
```bash
# Firebase CLIのインストール
npm install -g firebase-tools

# ログイン
firebase login

# プロジェクトの初期化（初回のみ）
firebase init firestore
```

#### 手順

1. **firestore.indexes.json をコピー**
   ```bash
   cp firebase/firestore.indexes.json firestore.indexes.json
   ```

2. **デプロイ**
   ```bash
   # 開発環境
   firebase deploy --only firestore:indexes --project sugarbeat-dev

   # 本番環境
   firebase deploy --only firestore:indexes --project sugarbeat-prod
   ```

3. **確認**
   ```bash
   firebase firestore:indexes --project sugarbeat-dev
   ```

### ⚠️ インデックス作成時の注意

#### 自動作成される単一フィールドインデックス
以下は**自動的に作成される**ため、手動で作成する必要はありません：
- `userId` (昇順)
- `createdAt` (降順)
- `recipientId` (昇順)

#### インデックスが必要なケース
アプリ実行時に以下のようなエラーが出た場合：

```
The query requires an index. You can create it here:
https://console.firebase.google.com/v1/r/project/YOUR_PROJECT/firestore/indexes?create_composite=...
```

**対処方法**:
1. エラーメッセージのURLをクリック
2. Firebaseコンソールが開き、必要なインデックスが自動で設定されます
3. 「インデックスを作成」をクリック

これにより、**必要なインデックスのみ**を作成できます。

---

## 4. 動作確認

### Firestore Rules のテスト

#### Firebase Console でテスト

1. **Firestore Database → ルール → シミュレータ**

2. **テスト1: 認証なしでの読み取り**
   ```
   場所: /posts/testPost123
   シミュレートの種類: 取得
   認証: なし

   期待結果: ❌ シミュレーションが失敗しました
   ```

3. **テスト2: 認証ありでの読み取り**
   ```
   場所: /posts/testPost123
   シミュレートの種類: 取得
   認証: 認証されたカスタムプロバイダ
   UID: testUser123

   期待結果: ✅ シミュレーションが成功しました
   ```

4. **テスト3: 他人のデータを更新**
   ```
   場所: /users/otherUser456
   シミュレートの種類: 更新
   認証: 認証されたカスタムプロバイダ
   UID: testUser123

   期待結果: ❌ シミュレーションが失敗しました
   ```

5. **テスト4: 自分のデータを更新**
   ```
   場所: /users/testUser123
   シミュレートの種類: 更新
   認証: 認証されたカスタムプロバイダ
   UID: testUser123

   期待結果: ✅ シミュレーションが成功しました
   ```

### Storage Rules のテスト

#### Xcodeで実機テスト

1. **アプリをビルド・実行**

2. **画像アップロードをテスト**
   - プロフィール画像の変更
   - 投稿に画像を添付（将来的な機能）

3. **エラーがないか確認**
   - Xcodeのコンソールでエラーをチェック
   - Firebase Console → Storage → ファイルが正しくアップロードされているか確認

### Indexes のテスト

#### アプリでクエリを実行

1. **フィード表示**
   - アプリでフィード画面を開く
   - 投稿が正しく表示されるか確認

2. **通知表示**
   - 通知画面を開く
   - 通知が正しく表示されるか確認

3. **エラーチェック**
   ```
   ❌ エラーが出る場合:
   "The query requires an index"

   → エラーメッセージのリンクをクリックしてインデックスを作成
   ```

---

## 🔒 セキュリティチェックリスト

設定完了後、以下を確認してください：

### Firestore Rules
- [ ] テストモードになっていない（`if true` がない）
- [ ] 認証が必須になっている（`isAuthenticated()` を使用）
- [ ] 所有者チェックが実装されている（`isOwner()` を使用）
- [ ] シミュレータでテスト済み

### Storage Rules
- [ ] テストモードになっていない
- [ ] 画像サイズ制限が設定されている（5MB）
- [ ] 画像形式の制限が設定されている
- [ ] ユーザーは自分のフォルダのみアクセス可能

### Indexes
- [ ] 必要な複合インデックスが作成されている
- [ ] インデックスのステータスが「有効」になっている
- [ ] アプリでクエリエラーが出ない

---

## 📊 設定後のモニタリング

### Firebase Console で確認すべき項目

#### 1. Usage Dashboard
```
Firebase Console → ホーム → 使用状況
```
- リクエスト数
- ストレージ使用量
- 異常なスパイク

#### 2. Firestore Usage
```
Firebase Console → Firestore Database → 使用状況
```
- 読み取り数（日次/月次）
- 書き込み数
- 削除数

#### 3. Storage Usage
```
Firebase Console → Storage → 使用状況
```
- ストレージ容量
- ダウンロード量
- アップロード数

### アラート設定（推奨）

```
Firebase Console → プロジェクトの設定 → 統合 → アラート
```

推奨アラート：
- Firestore読み取り: 100,000回/日を超えたら
- Storage容量: 10GBを超えたら
- 予算アラート: $10/月を超えたら

---

## ❓ トラブルシューティング

### 問題1: "Missing or insufficient permissions" エラー

**原因**: Rulesが正しく設定されていない

**解決方法**:
1. Firebase Console → Firestore → ルール
2. ルールが正しくコピペされているか確認
3. 「公開」ボタンを押したか確認

### 問題2: "The query requires an index" エラー

**原因**: 必要なインデックスがない

**解決方法**:
1. エラーメッセージのURLをクリック
2. 「インデックスを作成」をクリック
3. 作成完了を待つ（数分）

### 問題3: 画像アップロードが失敗する

**原因1**: Storage Rulesが正しくない
**解決方法**: Storage Rulesを再確認して公開

**原因2**: 画像サイズが5MBを超えている
**解決方法**: 画像を圧縮するか、Rulesの制限を変更

**原因3**: ファイル形式が画像ではない
**解決方法**: JPEG、PNGなどの画像形式を使用

### 問題4: インデックス作成が「作成中」のまま

**原因**: 大量のデータがある場合、時間がかかる

**解決方法**:
- 通常は数分で完了
- 30分以上かかる場合は、Firebase サポートに連絡

---

## 📚 参考リンク

- [Firestore Security Rules ドキュメント](https://firebase.google.com/docs/firestore/security/get-started)
- [Storage Security Rules ドキュメント](https://firebase.google.com/docs/storage/security)
- [Firestore Indexes ドキュメント](https://firebase.google.com/docs/firestore/query-data/indexing)
- [Firebase CLI リファレンス](https://firebase.google.com/docs/cli)

---

## ✅ 完了

以上でFirebaseのセットアップは完了です！

次のステップ:
1. アプリをビルド・実行
2. 各機能をテスト
3. Firebase Consoleで使用状況を監視
