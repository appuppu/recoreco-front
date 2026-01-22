import Foundation
import FirebaseCore
import FirebaseFirestore

enum AppEnvironment {
    case development
    case production

    // 環境切り替え（本番リリース時に.productionに変更）
    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

class FirebaseConfig {
    static let shared = FirebaseConfig()
    private static var isConfigured = false
    private static let configurationLock = NSLock()

    private init() {}

    // Ensure Firebase is configured (thread-safe, idempotent)
    static func ensureConfigured() {
        configurationLock.lock()
        defer { configurationLock.unlock() }

        guard !isConfigured else { return }

        shared.configure()
        isConfigured = true
    }

    func configure() {
        switch AppEnvironment.current {
        case .development:
            configureDevelopment()
        case .production:
            configureProduction()
        }
    }

    private func configureDevelopment() {
        // 開発環境用のFirebase設定
        // GoogleService-Info-Dev.plist を使用
        if let filePath = Bundle.main.path(forResource: "GoogleService-Info-Dev", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: filePath) {
            FirebaseApp.configure(options: options)
            print("🔥 Firebase configured for DEVELOPMENT")
        } else {
            // フォールバック: デフォルトのGoogleService-Info.plistを使用
            FirebaseApp.configure()
            print("🔥 Firebase configured for DEVELOPMENT (using default)")
        }

        // Configure Firestore settings BEFORE any Firestore access
        configureFirestoreSettings()
    }

    private func configureProduction() {
        // 本番環境用のFirebase設定
        // GoogleService-Info-Prod.plist を使用
        if let filePath = Bundle.main.path(forResource: "GoogleService-Info-Prod", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: filePath) {
            FirebaseApp.configure(options: options)
            print("🔥 Firebase configured for PRODUCTION")
        } else {
            // フォールバック: デフォルトのGoogleService-Info.plistを使用
            FirebaseApp.configure()
            print("🔥 Firebase configured for PRODUCTION (using default)")
        }

        // Configure Firestore settings BEFORE any Firestore access
        configureFirestoreSettings()
    }

    private func configureFirestoreSettings() {
        let db = Firestore.firestore()
        let settings = FirestoreSettings()

        // Enable offline persistence with persistent cache
        let persistentSettings = PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024 as NSNumber)
        settings.cacheSettings = persistentSettings

        db.settings = settings
        print("✅ Firestore configured with optimized cache settings")
    }

    var serverURL: String {
        switch AppEnvironment.current {
        case .development:
            return "http://192.168.0.2:8080/api"
        case .production:
            return "https://recoreco.net/api"
        }
    }

    var serverBaseURL: String {
        switch AppEnvironment.current {
        case .development:
            return "http://192.168.0.2:8080"
        case .production:
            return "https://recoreco.net"
        }
    }
}
