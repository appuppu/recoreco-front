# Universal Links セットアップ手順

プロフィールのディープリンク機能を有効にするための手順です。

## 📋 概要

- プロフィールURL: `https://appuppu.github.io/profile/{username}`
- アプリインストール済み → アプリで開く
- アプリ未インストール → ブラウザで開く

## 🔧 セットアップ

### 1. apple-app-site-association ファイルをGitHub Pagesに配置

1. GitHub Pagesリポジトリ（`appuppu/appuppu.github.io` または `docs`フォルダ）を開く

2. 以下の場所にファイルを配置：
   ```
   .well-known/apple-app-site-association
   ```
   または
   ```
   apple-app-site-association
   ```
   （両方に配置することを推奨）

3. ファイル内容（`apple-app-site-association`）:
   ```json
   {
     "applinks": {
       "apps": [],
       "details": [
         {
           "appID": "TEAMID.com.sugarbeat.SugarBeat",
           "paths": ["/profile/*"]
         }
       ]
     }
   }
   ```

4. **重要**: `TEAMID` を実際のTeam IDに置き換える
   - Xcodeで確認: `SugarBeat.xcodeproj` → TARGETS → SugarBeat → Signing & Capabilities → Team ID

5. GitHubにプッシュして公開

### 2. Xcodeで Associated Domains を設定

1. Xcode で `SugarBeat.xcodeproj` を開く

2. TARGETS → SugarBeat → Signing & Capabilities

3. 「+ Capability」をクリック → 「Associated Domains」を追加

4. Domainsに以下を追加：
   ```
   applinks:appuppu.github.io
   ```

5. プロジェクトを保存

### 3. 動作確認

1. アプリをビルドしてデバイスにインストール

2. Safariで以下のURLを開く：
   ```
   https://appuppu.github.io/profile/testuser
   ```
   （`testuser` は実際に存在するユーザー名に置き換え）

3. 「開く」をタップ → アプリが起動してプロフィール画面が表示されればOK

### 4. デバッグ

動作しない場合：

1. **apple-app-site-association ファイルの確認**
   ```bash
   curl https://appuppu.github.io/.well-known/apple-app-site-association
   ```
   または
   ```bash
   curl https://appuppu.github.io/apple-app-site-association
   ```
   正しいJSONが返ってくることを確認

2. **Appleのバリデーター**
   https://search.developer.apple.com/appsearch-validation-tool/
   でURLを検証

3. **Xcodeログ確認**
   ```
   🔗 [SugarBeatApp] Received URL: ...
   🔗 [DeepLinkManager] Handling URL: ...
   ```
   がコンソールに出力されるか確認

4. **デバイス再起動**
   Universal Linksのキャッシュをクリアするため

## ✅ エラーハンドリング

実装済み：
- ユーザーが存在しない → 「ユーザーが見つかりませんでした」
- ユーザーが削除済み → 「ユーザーが見つかりませんでした」
- ユーザーがブロック中 → 「このユーザーは表示できません」
- 不正なURL形式 → 「無効なリンク形式です」
- 不正なユーザー名 → 「無効なユーザー名です」

## 📱 使い方

1. プロフィールタブの右上の🔗ボタンをタップ
2. シェアシートが表示される
3. LINE、Twitter、メッセージなどで共有
4. 受け取った人がリンクをタップ → アプリで開く

## 🔒 セキュリティ

- ユーザー名は公開情報なので安全
- 既に英数字、ドット、アンダースコアのみに制限済み
- 不正なアクセスは全てエラーハンドリング済み
