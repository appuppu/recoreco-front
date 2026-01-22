# SugarBeat プロジェクトガイドライン

## 🔴 必須ルール

### ビルド確認
**コマンドラインでのビルドは禁止**
- `xcodebuild`コマンドは使用しない
- Xcodeとコマンドラインのキャッシュ競合を避けるため
- ビルド確認はユーザーがXcodeで実行する
- コード修正のみを行い、ビルドはXcodeに任せる

## プロジェクト情報

### 技術スタック
- **言語**: Swift 5.9
- **最小iOS**: 16.0
- **フレームワーク**: SwiftUI
- **バックエンド**: Firebase (Auth, Firestore, Storage)
- **依存管理**: CocoaPods
- **広告**: Google Mobile Ads
- **音楽**: Apple Music API

### デプロイメントターゲット
- iOS 16.0以降をサポート
- iOS 16.4以降のAPIを使用する場合は`#available(iOS 16.4, *)`で条件分岐すること

### ビルド最適化
MacBookの熱対策として:
- 不要なデバッグログは削除
- ビルド時は他の重いアプリを閉じる
- DerivedDataを定期的にクリーン: `rm -rf ~/Library/Developer/Xcode/DerivedData/*`

## コーディング規約

### UI関連
1. **モーダル画面（Sheet）の背景色**
   - iOS 16.4以降: `.presentationBackground(Color.black)`と`.presentationCornerRadius(20)`を使用
   - iOS 16.0-16.3: 条件分岐で対応

2. **リフレッシュインジケーター**
   - `.tint(.white)`を使用（暗い背景で見やすくするため）

3. **背景色の統一**
   - メイン背景: `Color.black`
   - カード背景: `Color(white: 0.15)`
   - タブバー: `Color.black` (透明度なし)

### デバッグログ
- 🔍 prefix: データ取得・表示の調査用
- ✅ prefix: 成功時
- ❌ prefix: エラー時
- 📥 prefix: データ読み込み時

### Firebase Rules
- 未認証ユーザーでも投稿とチャンネルは読み取り可能（発見タブ用）
- 認証が必要な機能: いいね、コメント、フォロー、投稿作成

## よくある問題と対処法

### 1. ビルドエラー: "presentationBackground is only available in iOS 16.4"
**原因**: iOS 16.4以降のAPIを使用している
**対処**: `if #available(iOS 16.4, *)`で条件分岐

### 2. プロフィール画像が表示されない
**確認事項**:
- `userProfileImageUrl`フィールドがChannelモデルに存在するか
- Firestoreに実際に画像URLが保存されているか
- デバッグログでURLを確認

### 3. 白い線が見える
**原因**: Sheetのデフォルト背景が白
**対処**: `.presentationBackground(Color.black)`を追加

### 4. MacBookが熱くなる
**原因**: Xcodeのビルドプロセスが重い
**対処**:
- DerivedDataをクリーン
- Xcodeを再起動
- 他のアプリを閉じる
- ビルドは必要最小限に

## 記憶させたいルールの追加方法

このファイル（`.claude/project_guidelines.md`）を編集して、新しいルールやベストプラクティスを追加してください。Claude Codeは自動的にこのファイルを参照します。
