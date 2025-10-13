# Xcode プロジェクトセットアップ手順

Xcodeが起動したと思います。以下の手順でプロジェクトを作成してください。

## 手順1: 新規プロジェクト作成

1. Xcodeのメニューから **File** → **New** → **Project...** を選択
2. **iOS** タブを選択
3. **App** を選択して **Next** をクリック

## 手順2: プロジェクト設定

以下の情報を入力：

- **Product Name**: `SugarBeat`
- **Team**: （あなたのApple Developer Team、なければNone）
- **Organization Identifier**: `com.sugarbeat`（または任意）
- **Bundle Identifier**: 自動生成される（例: com.sugarbeat.SugarBeat）
- **Interface**: `SwiftUI` を選択 ⚠️重要
- **Language**: `Swift` を選択
- **Storage**: `None` を選択
- **Include Tests**: チェックを外してOK

**Next** をクリック

## 手順3: 保存場所

1. **Create Git repository on my Mac** のチェックは外してOK
2. 保存場所: `/Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front` を選択
3. **Create** をクリック

⚠️ 注意：既存の `SugarBeat` フォルダと名前が重複する可能性があります。
その場合は、一旦別の名前（例：`SugarBeatApp`）で作成してから、後で統合します。

## 手順4: 既存ファイルの統合

プロジェクトが作成されたら：

### A. 既存ファイルを使う場合（推奨）

1. Xcodeのプロジェクトナビゲーター（左側）で、自動生成された `ContentView.swift` を削除
2. ファイルメニューから **Add Files to "SugarBeat"...** を選択
3. 既存の `SugarBeat` フォルダ内の以下を選択して追加：
   - `Models` フォルダ
   - `Services` フォルダ
   - `ViewModels` フォルダ
   - `Views` フォルダ
   - `Assets.xcassets` （既存のものと置き換え）
   - `Info.plist` （必要に応じて）

4. **Options** で以下を確認：
   - ✅ **Copy items if needed** をチェック
   - ✅ **Create groups** を選択
   - ✅ **Add to targets: SugarBeat** をチェック

### B. SugarBeatApp.swift の更新

既存の `SugarBeatApp.swift` の内容を、自動生成された同名ファイルに上書き：

```swift
import SwiftUI

@main
struct SugarBeatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 手順5: Build Settings の確認

1. プロジェクトナビゲーターで一番上の **プロジェクトファイル**（青いアイコン）をクリック
2. **TARGETS** の下の **SugarBeat** を選択
3. **Signing & Capabilities** タブを選択
4. **Automatically manage signing** をチェック
5. **Team** を選択（Personal Teamでも可）

## 手順6: ビルド＆実行

1. 左上のScheme（デバイス選択）で **iPhone 15 Pro**（またはお好みのシミュレーター）を選択
2. **⌘ + R** または **Product** → **Run** でビルド＆実行

## トラブルシューティング

### エラー: "No such module 'SwiftUI'"

- iOS Deployment Target を確認：iOS 16.0 以上に設定

### エラー: ファイルが見つからない

- プロジェクトナビゲーターでファイルが赤色になっている場合、右クリック → **Show in Finder** で場所を確認
- 正しいパスを設定し直す

### ビルドエラー

```bash
# 一旦クリーン
⌘ + Shift + K (Product → Clean Build Folder)

# 再ビルド
⌘ + B
```

## より簡単な方法（コマンドライン）

もし上記が面倒な場合、以下のコマンドで自動化できます（試験的）：

```bash
cd /Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front

# xcodegenがインストールされている場合
# brew install xcodegen
# （設定ファイルを作成してから）
# xcodegen generate
```

---

問題が発生した場合はお知らせください！
