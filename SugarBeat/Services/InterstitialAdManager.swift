//
//  InterstitialAdManager.swift
//  SugarBeat
//

import Foundation
import GoogleMobileAds
import UIKit

@MainActor
class InterstitialAdManager: NSObject, ObservableObject {
    static let shared = InterstitialAdManager()

    @Published var isLoading = false
    @Published var isAdReady = false

    private var interstitialAd: InterstitialAd?
    private let adUnitID: String

    private override init() {
        #if DEBUG
        // テスト用のUnit ID (Compose42用)
        adUnitID = "ca-app-pub-3940256099942544/1033173712"
        print("🎬 [InterstitialAdManager] Initialized with TEST Ad Unit ID: \(adUnitID)")
        #else
        // 本番用のUnit ID
        adUnitID = "ca-app-pub-3107120992746486/9167451412"
        print("🎬 [InterstitialAdManager] Initialized with PRODUCTION Ad Unit ID: \(adUnitID)")
        #endif
        super.init()
        print("🎬 [InterstitialAdManager] Initialization complete")
    }

    func load() {
        guard !isLoading else {
            print("🎬 [InterstitialAdManager] Already loading, skipping")
            return
        }

        print("🎬 [InterstitialAdManager] Loading ad...")
        isLoading = true
        isAdReady = false
        interstitialAd = nil

        let request = Request()

        InterstitialAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false

                if let error = error {
                    print("🎬 [InterstitialAdManager] ❌ Failed to load ad: \(error.localizedDescription)")
                    return
                }

                guard let ad = ad else {
                    print("🎬 [InterstitialAdManager] ❌ Ad is nil")
                    return
                }

                self.interstitialAd = ad
                self.interstitialAd?.fullScreenContentDelegate = self
                self.isAdReady = true
                print("🎬 [InterstitialAdManager] ✅ Ad loaded successfully")
            }
        }
    }

    func show(from viewController: UIViewController?) {
        guard let interstitialAd = interstitialAd else {
            print("🎬 [InterstitialAdManager] ❌ Ad not ready")
            return
        }

        guard let viewController = viewController else {
            print("🎬 [InterstitialAdManager] ❌ ViewController is nil")
            return
        }

        print("🎬 [InterstitialAdManager] Showing ad...")
        interstitialAd.present(from: viewController)
    }

    func getRootViewController() -> UIViewController? {
        let connectedScenes = UIApplication.shared.connectedScenes
        let windowScenes = connectedScenes.compactMap({ $0 as? UIWindowScene })
        let windows = windowScenes.flatMap({ $0.windows })
        let keyWindow = windows.first(where: { $0.isKeyWindow })
        return keyWindow?.rootViewController
    }
}

// MARK: - FullScreenContentDelegate
extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("🎬 [InterstitialAdManager] Ad did record impression")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        print("🎬 [InterstitialAdManager] Ad did record click")
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("🎬 [InterstitialAdManager] ❌ Failed to present: \(error.localizedDescription)")
        isAdReady = false
        interstitialAd = nil
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🎬 [InterstitialAdManager] Will present full screen content")
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🎬 [InterstitialAdManager] Will dismiss full screen content")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🎬 [InterstitialAdManager] Did dismiss full screen content")
        isAdReady = false
        interstitialAd = nil
        // 次の広告を事前にロード
        load()
    }
}
