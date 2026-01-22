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

// MARK: - Feed Native Ad View

/// フィード用ネイティブ広告ビュー
struct FeedNativeAdView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat

    init(adUnitID: String = AdConfig.feedAdUnitId, width: CGFloat) {
        self.adUnitID = adUnitID
        self.width = width
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.translatesAutoresizingMaskIntoConstraints = false

        // 広告ローダーを作成
        let adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: getRootViewController(),
            adTypes: [.native],
            options: nil
        )
        adLoader.delegate = context.coordinator
        context.coordinator.adView = adView
        context.coordinator.width = width

        // 広告をロード
        let request = Request()
        adLoader.load(request)

        print("FeedNativeAdView: Loading native ad")

        return adView
    }

    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // 必要に応じて更新
    }

    private func getRootViewController() -> UIViewController? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            return rootViewController
        }
        return nil
    }

    class Coordinator: NSObject, NativeAdLoaderDelegate {
        var adView: NativeAdView?
        var width: CGFloat = 0

        func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
            print("FeedNativeAdView: Native ad loaded successfully")

            guard let adView = adView else { return }

            // ネイティブ広告を表示するカスタムビューを作成
            let customAdView = createCustomAdView(nativeAd: nativeAd, width: width)

            // adViewに追加
            adView.subviews.forEach { $0.removeFromSuperview() }
            adView.addSubview(customAdView)

            NSLayoutConstraint.activate([
                customAdView.topAnchor.constraint(equalTo: adView.topAnchor),
                customAdView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
                customAdView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
                customAdView.bottomAnchor.constraint(equalTo: adView.bottomAnchor)
            ])

            adView.nativeAd = nativeAd
        }

        func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
            print("FeedNativeAdView: Failed to load ad: \(error.localizedDescription)")
        }

        private func createCustomAdView(nativeAd: NativeAd, width: CGFloat) -> UIView {
            let containerView = UIView()
            containerView.translatesAutoresizingMaskIntoConstraints = false
            containerView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
            containerView.layer.cornerRadius = 16
            containerView.clipsToBounds = true

            // 広告ラベル
            let adLabel = UILabel()
            adLabel.text = "広告"
            adLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            adLabel.textColor = UIColor.white.withAlphaComponent(0.6)
            adLabel.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            adLabel.textAlignment = .center
            adLabel.layer.cornerRadius = 4
            adLabel.clipsToBounds = true
            adLabel.translatesAutoresizingMaskIntoConstraints = false

            // 画像ビュー
            let imageView = MediaView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = 12
            imageView.clipsToBounds = true
            imageView.mediaContent = nativeAd.mediaContent

            // 見出し
            let headlineLabel = UILabel()
            headlineLabel.text = nativeAd.headline
            headlineLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
            headlineLabel.textColor = .white
            headlineLabel.numberOfLines = 2
            headlineLabel.translatesAutoresizingMaskIntoConstraints = false

            // 説明文
            let bodyLabel = UILabel()
            bodyLabel.text = nativeAd.body
            bodyLabel.font = UIFont.systemFont(ofSize: 14)
            bodyLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            bodyLabel.numberOfLines = 2
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false

            // CTAボタン
            let ctaButton = UIButton(type: .system)
            ctaButton.setTitle(nativeAd.callToAction, for: .normal)
            ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            ctaButton.setTitleColor(.white, for: .normal)
            ctaButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            ctaButton.layer.cornerRadius = 8
            ctaButton.translatesAutoresizingMaskIntoConstraints = false

            // レイアウト
            containerView.addSubview(imageView)
            containerView.addSubview(adLabel)
            containerView.addSubview(headlineLabel)
            containerView.addSubview(bodyLabel)
            containerView.addSubview(ctaButton)

            NSLayoutConstraint.activate([
                // 広告ラベル
                adLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
                adLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
                adLabel.widthAnchor.constraint(equalToConstant: 40),
                adLabel.heightAnchor.constraint(equalToConstant: 20),

                // 画像
                imageView.topAnchor.constraint(equalTo: adLabel.bottomAnchor, constant: 8),
                imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
                imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
                imageView.heightAnchor.constraint(equalToConstant: width - 24),

                // 見出し
                headlineLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
                headlineLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
                headlineLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

                // 説明文
                bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 4),
                bodyLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
                bodyLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

                // CTAボタン
                ctaButton.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 12),
                ctaButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
                ctaButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
                ctaButton.heightAnchor.constraint(equalToConstant: 44),
                ctaButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
            ])

            return containerView
        }
    }
}
