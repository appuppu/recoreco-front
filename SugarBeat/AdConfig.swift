import Foundation

struct AdConfig {
    // アプリID
    static let appID = "ca-app-pub-3107120992746486~2414005410"

    // 本番用広告ユニットID
    static let productionBannerID = "ca-app-pub-3107120992746486/6285801810"

    // テスト用広告ユニットID
    static let testBannerID = "ca-app-pub-3940256099942544/2435281174"

    // テストモード切り替え（本番リリース時にfalseに変更）
    static let isTestMode = true

    // スクリーンショット撮影時に広告を非表示にする（撮影後はfalseに戻す）
    static let hideAdsForScreenshot = false

    // 広告を表示するかどうか
    static var shouldShowAds: Bool {
        // テストモードまたはスクリーンショット撮影時は非表示
        return !isTestMode && !hideAdsForScreenshot
    }

    static var bannerAdUnitID: String {
        return isTestMode ? testBannerID : productionBannerID
    }
}
