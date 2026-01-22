import Foundation

/// AdMob広告設定
struct AdConfig {

    // MARK: - App ID
    static let appId = "ca-app-pub-3107120992746486~2414005410"

    // MARK: - Unit IDs

    /// バナー広告のユニットID
    static var bannerAdUnitId: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2435281174" // テスト用ユニットID
        #else
        return "ca-app-pub-3107120992746486/6285801810" // 本番用ユニットID
        #endif
    }

    /// フィード広告（ネイティブ広告）のユニットID
    static var feedAdUnitId: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511" // テスト用ネイティブ広告
        #else
        return "ca-app-pub-3107120992746486/3547387325" // 本番用ユニットID
        #endif
    }

    // MARK: - Ad Sizes

    /// バナー広告の高さ
    static let bannerHeight: CGFloat = 50

    // MARK: - Ad Display Control

    /// 広告を表示するかどうか
    static var shouldShowAds: Bool {
        return true
    }
}
