//
//  FeedAdManager.swift
//  SugarBeat
//

import Foundation
import GoogleMobileAds

class FeedAdManager: NSObject, ObservableObject {
    static let shared = FeedAdManager()

    @MainActor @Published var loadedAds: [NativeAd] = []
    @MainActor @Published var isLoading = false

    private var adLoader: AdLoader?
    private let adUnitID: String
    private var retryCount = 0
    private let maxRetries = 3

    private override init() {
        #if DEBUG
        // テスト用のUnit ID
        adUnitID = "ca-app-pub-3940256099942544/3986624511"
        print("🎵 FeedAdManager - Initialized with TEST Ad Unit ID: \(adUnitID)")
        #else
        // 本番用のUnit ID
        adUnitID = "ca-app-pub-3107120992746486/3547387325"
        print("🎵 FeedAdManager - Initialized with PRODUCTION Ad Unit ID: \(adUnitID)")
        #endif
        super.init()
        print("🎵 FeedAdManager - Initialization complete")
    }

    @MainActor
    func loadAds(count: Int = 5, isRetry: Bool = false) {
        guard !isLoading else {
            print("🎵 FeedAdManager - Already loading, skipping")
            return
        }

        print("🎵 FeedAdManager - loadAds called (retry: \(isRetry), attempt: \(retryCount + 1)/\(maxRetries))")
        print("🎵 FeedAdManager - Ad Unit ID: \(adUnitID)")
        print("🎵 FeedAdManager - Requested count: \(count)")

        // AdMobの初期化完了を待つ
        let initStatus = MobileAds.shared.initializationStatus
        print("🎵 FeedAdManager - AdMob initialization status: \(initStatus.adapterStatusesByClassName)")

        if initStatus.adapterStatusesByClassName.isEmpty {
            print("🎵 FeedAdManager - ⚠️ AdMob not initialized yet, waiting...")
            MobileAds.shared.start { [weak self] status in
                print("🎵 FeedAdManager - ✅ AdMob initialized, retrying load")
                Task { @MainActor in
                    self?.loadAds(count: count, isRetry: isRetry)
                }
            }
            return
        }

        isLoading = true
        if !isRetry {
            loadedAds = []
            retryCount = 0
        }

        // 複数広告読み込みオプション
        let multipleAdsOptions = MultipleAdsAdLoaderOptions()
        multipleAdsOptions.numberOfAds = count
        print("🎵 FeedAdManager - MultipleAdsOptions configured: \(count) ads")

        // Native広告ビューオプション
        let nativeAdViewOptions = NativeAdViewAdOptions()
        nativeAdViewOptions.preferredAdChoicesPosition = .topRightCorner
        print("🎵 FeedAdManager - NativeAdViewOptions configured")

        // ビデオオプション
        let videoOptions = VideoOptions()
        videoOptions.shouldStartMuted = true
        videoOptions.areCustomControlsRequested = false
        print("🎵 FeedAdManager - VideoOptions configured")

        // rootViewControllerを取得
        let connectedScenes = UIApplication.shared.connectedScenes
        let windowScenes = connectedScenes.compactMap({ $0 as? UIWindowScene })
        let windows = windowScenes.flatMap({ $0.windows })
        let keyWindow = windows.first(where: { $0.isKeyWindow })

        guard let rootVC = keyWindow?.rootViewController else {
            print("🎵 FeedAdManager - ❌ Failed to get rootViewController")
            isLoading = false
            return
        }

        print("🎵 FeedAdManager - ✅ Root view controller: \(type(of: rootVC))")

        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [multipleAdsOptions, nativeAdViewOptions, videoOptions]
        )

        adLoader?.delegate = self
        let request = Request()

        print("🎵 FeedAdManager - ✅ Request configured")

        adLoader?.load(request)
        print("🎵 FeedAdManager - ✅ Started loading \(count) ads with Unit ID: \(adUnitID)")
    }

    @MainActor
    func getNextAd() -> NativeAd? {
        guard !loadedAds.isEmpty else {
            // 広告がない場合は新しく読み込む
            print("🎵 FeedAdManager - No ads available, loading new ads")
            Task {
                await MainActor.run {
                    loadAds()
                }
            }
            return nil
        }

        let ad = loadedAds.removeFirst()
        print("🎵 FeedAdManager - Providing ad, remaining: \(loadedAds.count)")

        // 残りが少なくなったら補充
        if loadedAds.count < 3 {
            Task {
                await MainActor.run {
                    loadAds()
                }
            }
        }

        return ad
    }
}

extension FeedAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in
            print("🎵 FeedAdManager - ✅ Ad loaded successfully")
            print("🎵 FeedAdManager - Ad headline: \(nativeAd.headline ?? "N/A")")
            loadedAds.append(nativeAd)
            print("🎵 FeedAdManager - Total loaded ads: \(loadedAds.count)")

            // 成功したらリトライカウントをリセット
            retryCount = 0
        }
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in
            print("🎵 FeedAdManager - ❌ Failed to load ad")
            print("🎵 FeedAdManager - Error description: \(error.localizedDescription)")

            let nsError = error as NSError
            print("🎵 FeedAdManager - Error domain: \(nsError.domain)")
            print("🎵 FeedAdManager - Error code: \(nsError.code)")

            // ResponseInfoの詳細を出力
            if let responseInfo = nsError.userInfo["gad_response_info"] as? ResponseInfo {
                print("🎵 FeedAdManager - Response ID: \(responseInfo.responseIdentifier ?? "null")")
                print("🎵 FeedAdManager - Ad Network Class Name: \(responseInfo.loadedAdNetworkResponseInfo?.adNetworkClassName ?? "null")")

                // 各アダプターの状態を確認
                for adapterInfo in responseInfo.adNetworkInfoArray {
                    print("🎵 FeedAdManager - Adapter: \(adapterInfo.adNetworkClassName)")
                    print("   - Latency: \(adapterInfo.latency)")
                    if let error = adapterInfo.error {
                        print("   - Error: \(error.localizedDescription)")
                    }
                }
            }

            // AdMobの初期化状態を確認
            let initStatus = MobileAds.shared.initializationStatus
            print("🎵 FeedAdManager - Current AdMob status:")
            for (className, status) in initStatus.adapterStatusesByClassName {
                print("   - \(className): \(status.state.rawValue) - \(status.description)")
            }

            // エラーコード11 (Internal error) の詳細を確認とリトライ
            if nsError.code == 11 {
                print("🎵 FeedAdManager - ⚠️ Error 11 (Internal error) - This may be due to:")
                print("   - AdMob SDK not fully initialized")
                print("   - Network connectivity issues")
                print("   - No ad inventory available")
                print("   - AdMob account configuration issues")

                // リトライロジック（最大回数未満の場合のみ）
                if retryCount < maxRetries - 1 {  // maxRetries=3なので、0,1,2回目のエラーでリトライ
                    retryCount += 1
                    let delay = Double(retryCount) * 3.0 // 3秒、6秒と段階的に遅延（延長）
                    print("🎵 FeedAdManager - 🔄 Retrying in \(delay) seconds (attempt \(retryCount + 1)/\(maxRetries))")

                    isLoading = false

                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        await loadAds(count: 5, isRetry: true)
                    }
                    return
                } else {
                    print("🎵 FeedAdManager - ❌ Max retries reached, giving up")
                    retryCount = 0  // 次回のloadAds呼び出しのためにリセット
                    isLoading = false
                }
            } else {
                print("🎵 FeedAdManager - ❌ Non-retryable error code: \(nsError.code)")
                isLoading = false
            }
        }
    }

    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        Task { @MainActor in
            print("🎵 FeedAdManager - 🏁 Finished loading ads")
            print("🎵 FeedAdManager - Total ads loaded: \(loadedAds.count)")
            isLoading = false
        }
    }
}
