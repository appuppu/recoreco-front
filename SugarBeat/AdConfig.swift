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

    static var bannerAdUnitID: String {
        return isTestMode ? testBannerID : productionBannerID
    }
}
