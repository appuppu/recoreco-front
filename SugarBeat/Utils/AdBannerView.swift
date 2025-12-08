import SwiftUI
import GoogleMobileAds

/// GoogleAdMobバナー広告ビュー
struct AdBannerView: UIViewRepresentable {
    let adUnitID: String
    let adSize: AdSize

    init(adUnitID: String = AdConfig.bannerAdUnitId, adSize: AdSize = AdSizeBanner) {
        self.adUnitID = adUnitID
        self.adSize = adSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: adSize)
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator

        // 背景色を黒に設定
        bannerView.backgroundColor = .black

        // ViewControllerを即座に設定
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            bannerView.rootViewController = rootViewController

            // 少し遅延させてから広告をロード
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let request = Request()
                bannerView.load(request)

                print("AdBannerView: Loading ad with unit ID: \(adUnitID)")
            }
        } else {
            print("AdBannerView: ERROR - Could not find root view controller")
        }

        return bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // 必要に応じて広告を更新
    }

    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("AdBannerView: Ad loaded successfully")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("AdBannerView: Failed to load ad with error: \(error.localizedDescription)")
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            print("AdBannerView: Ad impression recorded")
        }

        func bannerViewWillPresentScreen(_ bannerView: BannerView) {
            print("AdBannerView: Will present screen")
        }

        func bannerViewWillDismissScreen(_ bannerView: BannerView) {
            print("AdBannerView: Will dismiss screen")
        }

        func bannerViewDidDismissScreen(_ bannerView: BannerView) {
            print("AdBannerView: Did dismiss screen")
        }
    }
}

/// AdMobマネージャー
@MainActor
class AdMobManager: ObservableObject {
    static let shared = AdMobManager()

    private init() {}

    /// AdMobを初期化
    func initialize() {
        MobileAds.shared.start { status in
            print("AdMob initialized with status: \(status.adapterStatusesByClassName)")
        }
    }
}
