import SwiftUI
import GoogleMobileAds

/// GoogleAdMobバナー広告ビュー
struct AdBannerView: UIViewRepresentable {
    let adUnitID: String
    let adSize: GADAdSize

    init(adUnitID: String = AdConfig.bannerAdUnitId, adSize: GADAdSize = .banner) {
        self.adUnitID = adUnitID
        self.adSize = adSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GADBannerView {
        let bannerView = GADBannerView(adSize: adSize)
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator

        // 背景色を設定
        bannerView.backgroundColor = UIColor.clear

        // ViewControllerを即座に設定
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            bannerView.rootViewController = rootViewController

            // 少し遅延させてから広告をロード
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let request = GADRequest()
                bannerView.load(request)

                print("AdBannerView: Loading ad with unit ID: \(adUnitID)")
            }
        } else {
            print("AdBannerView: ERROR - Could not find root view controller")
        }

        return bannerView
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // 必要に応じて広告を更新
    }

    class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            print("AdBannerView: Ad loaded successfully")
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("AdBannerView: Failed to load ad with error: \(error.localizedDescription)")
        }

        func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
            print("AdBannerView: Ad impression recorded")
        }

        func bannerViewWillPresentScreen(_ bannerView: GADBannerView) {
            print("AdBannerView: Will present screen")
        }

        func bannerViewWillDismissScreen(_ bannerView: GADBannerView) {
            print("AdBannerView: Will dismiss screen")
        }

        func bannerViewDidDismissScreen(_ bannerView: GADBannerView) {
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
        GADMobileAds.sharedInstance().start { status in
            print("AdMob initialized with status: \(status.adapterStatusesByClassName)")
        }
    }
}
