import Foundation
import FirebaseFirestore

/// アプリのバージョンチェックを管理するマネージャー
///
/// Firestore の `config/app` ドキュメントから「最低必須バージョン」を読み取り、
/// 現在のアプリバージョンと比較して強制アップデートが必要かを判定する。
///
/// Firestore 側のドキュメント構造（手動で1つ作成する）:
///   コレクション: config
///   ドキュメントID: app
///   フィールド:
///     - minimumVersion: String   例 "1.2.0"  これ未満は強制アップデート
///     - latestVersion:  String   例 "1.3.0"  任意アップデート案内（任意・未設定可）
///     - appStoreUrl:    String    App Store の更新ページURL（任意）
///
/// ドキュメントが存在しない／読み取り失敗の場合は「アップデート不要」とみなし、
/// アプリの起動を妨げない（フェイルセーフ）。
@MainActor
class AppVersionManager: ObservableObject {
    static let shared = AppVersionManager()

    /// 強制アップデートが必要か
    @Published var isUpdateRequired = false
    /// App Store の更新ページURL（Firestore で上書き可能、未設定ならデフォルト）
    @Published var appStoreUrl: String = AppVersionManager.defaultAppStoreUrl

    private let db = Firestore.firestore()
    private let configCollection = "config"
    private let configDocument = "app"

    // 「音楽SNS レコレコ」App Store ページ（App ID: 6754846506）
    private static let defaultAppStoreUrl = "https://apps.apple.com/app/id6754846506"

    private init() {}

    /// 現在のアプリのバージョン文字列（例 "1.1.2"）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 起動時に呼び出す。Firestore の設定を読み、強制アップデートが必要かを判定する。
    func checkForRequiredUpdate() async {
        do {
            let snapshot = try await db.collection(configCollection).document(configDocument).getDocument()

            guard let data = snapshot.data() else {
                // 設定ドキュメントが無い → アップデート不要として扱う
                print("ℹ️ [AppVersionManager] config/app が存在しません。アップデートチェックをスキップ")
                isUpdateRequired = false
                return
            }

            if let url = data["appStoreUrl"] as? String, !url.isEmpty {
                appStoreUrl = url
            }

            guard let minimumVersion = data["minimumVersion"] as? String else {
                print("ℹ️ [AppVersionManager] minimumVersion が未設定。アップデートチェックをスキップ")
                isUpdateRequired = false
                return
            }

            let required = AppVersionManager.isVersion(currentVersion, lessThan: minimumVersion)
            isUpdateRequired = required

            print("🔢 [AppVersionManager] currentVersion=\(currentVersion), minimumVersion=\(minimumVersion), updateRequired=\(required)")
        } catch {
            // 読み取り失敗時はアプリを止めない（フェイルセーフ）
            print("⚠️ [AppVersionManager] バージョン設定の取得に失敗: \(error)")
            isUpdateRequired = false
        }
    }

    /// セマンティックバージョン比較。`lhs < rhs` なら true。
    /// "1.2" や "1.2.0.1" のように桁数が異なっても比較できるよう、足りない桁は 0 とみなす。
    static func isVersion(_ lhs: String, lessThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)

        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l != r {
                return l < r
            }
        }
        return false // 等しい
    }
}
