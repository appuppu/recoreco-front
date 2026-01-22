# Firebase移行セットアップガイド

## 概要
このガイドでは、SugarBeatアプリをFirebaseに移行し、Google認証とApple認証を追加するための手順を説明します。

## 完了したコード変更

### 1. 追加・変更されたファイル
- ✅ `SugarBeat/Utils/FirebaseConfig.swift` - 環境別Firebase設定管理
- ✅ `SugarBeat/Models/AuthModels.swift` - Google/Apple認証用モデル追加
- ✅ `SugarBeat/Services/APIClient.swift` - Google/Apple認証エンドポイント追加
- ✅ `SugarBeat/Services/AuthManager.swift` - Google/Apple認証機能追加
- ✅ `SugarBeat/Views/LoginView.swift` - Google/Appleログインボタン追加
- ✅ `SugarBeat/Views/SignUpView.swift` - Google/Apple登録ボタン追加
- ✅ `SugarBeat/SugarBeatApp.swift` - Firebase初期化追加
- ✅ `Podfile` - Firebase/GoogleSignIn依存関係追加

## 次のステップ

### 1. 依存関係のインストール

```bash
cd /Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front
pod install
```

### 2. Firebase プロジェクトの作成

#### 開発環境用
1. [Firebase Console](https://console.firebase.google.com/) にアクセス
2. 新しいプロジェクトを作成（例: `sugarbeat-dev`）
3. iOS アプリを追加
   - Bundle ID: `your.bundle.id.dev`（開発用）
4. `GoogleService-Info.plist` をダウンロード
5. ファイル名を `GoogleService-Info-Dev.plist` にリネーム
6. Xcodeプロジェクトの `SugarBeat` フォルダに追加（Copy items if needed にチェック）

#### 本番環境用
1. [Firebase Console](https://console.firebase.google.com/) にアクセス
2. 新しいプロジェクトを作成（例: `sugarbeat-prod`）
3. iOS アプリを追加
   - Bundle ID: `your.bundle.id`（本番用）
4. `GoogleService-Info.plist` をダウンロード
5. ファイル名を `GoogleService-Info-Prod.plist` にリネーム
6. Xcodeプロジェクトの `SugarBeat` フォルダに追加（Copy items if needed にチェック）

### 3. Google Sign-In の設定

#### Firebase Console での設定
1. Firebase Console で各プロジェクト（dev/prod）を開く
2. Authentication → Sign-in method に移動
3. Google を有効化
4. プロジェクトのサポートメール設定

#### Xcode での設定
1. `GoogleService-Info-Dev.plist` と `GoogleService-Info-Prod.plist` を開く
2. `REVERSED_CLIENT_ID` の値をコピー
3. Xcode プロジェクトの Info.plist に追加:
   - URL Types → URL Schemes に `REVERSED_CLIENT_ID` を追加

または、Xcodeの Target → Info → URL Types で設定:
- Identifier: `com.googleusercontent.apps.YOUR_CLIENT_ID`
- URL Schemes: `REVERSED_CLIENT_ID の値`

### 4. Apple Sign-In の設定

#### Apple Developer での設定
1. [Apple Developer](https://developer.apple.com/) にログイン
2. Certificates, Identifiers & Profiles に移動
3. Identifiers → App IDs で該当アプリを選択
4. Sign In with Apple を有効化
5. 保存

#### Firebase Console での設定
1. Firebase Console で各プロジェクト（dev/prod）を開く
2. Authentication → Sign-in method に移動
3. Apple を有効化

#### Xcode での設定
1. Target → Signing & Capabilities
2. `+ Capability` をクリック
3. `Sign in with Apple` を追加

### 5. Info.plist の設定

`Info.plist` に以下を追加（必要に応じて）:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>REVERSED_CLIENT_ID の値</string>
        </array>
    </dict>
</array>

<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
```

### 6. バックエンドの設定

バックエンド（Spring Boot）に以下のエンドポイントを実装してください：

#### Google認証エンドポイント
```
POST /api/auth/google
Body: {
  "idToken": "string",
  "username": "string?" (オプション)
}
Response: AuthResponse
```

#### Apple認証エンドポイント
```
POST /api/auth/apple
Body: {
  "identityToken": "string",
  "authorizationCode": "string",
  "username": "string?",
  "email": "string?"
}
Response: AuthResponse
```

### 7. ビルドとテスト

1. Xcodeでプロジェクトをクリーン: `Cmd + Shift + K`
2. ビルド: `Cmd + B`
3. シミュレーターで実行してテスト
4. 実機でテスト（Apple Sign-Inは実機のみ）

## 環境の切り替え

### 開発環境
- `#if DEBUG` により自動的に開発環境が選択されます
- `GoogleService-Info-Dev.plist` が使用されます
- API URL: `http://192.168.0.2:8080/api`

### 本番環境
- リリースビルドでは自動的に本番環境が選択されます
- `GoogleService-Info-Prod.plist` が使用されます
- API URL: `https://recoreco.net/api`

手動で環境を切り替える場合は、`SugarBeat/Utils/FirebaseConfig.swift` の `AppEnvironment.current` を変更してください。

## トラブルシューティング

### Google Sign-In が動作しない
- `REVERSED_CLIENT_ID` が正しく設定されているか確認
- Bundle ID が Firebase Console の設定と一致しているか確認
- `pod install` を実行したか確認

### Apple Sign-In が動作しない
- Apple Developer で Sign In with Apple が有効になっているか確認
- Xcode の Signing & Capabilities に Sign in with Apple が追加されているか確認
- 実機でテストしているか確認（シミュレーターでは制限あり）

### ビルドエラー
- `pod install` を実行したか確認
- Xcode でクリーンビルド（Cmd + Shift + K）を実行
- Derived Data を削除: `rm -rf ~/Library/Developer/Xcode/DerivedData`

## 注意事項

1. **GoogleService-Info.plist ファイルはGitにコミットしないでください**
   - `.gitignore` に追加してください:
     ```
     **/GoogleService-Info-Dev.plist
     **/GoogleService-Info-Prod.plist
     ```

2. **セキュリティ**
   - Firebase API キーは公開されても問題ありませんが、Security Rules を適切に設定してください
   - バックエンドでトークン検証を必ず行ってください

3. **テスト**
   - 各認証方法（Email、Google、Apple）で正常に登録・ログインできることを確認
   - 開発環境と本番環境の両方でテスト

## 参考リンク

- [Firebase iOS Setup](https://firebase.google.com/docs/ios/setup)
- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios)
- [Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
- [Firebase Authentication](https://firebase.google.com/docs/auth)
