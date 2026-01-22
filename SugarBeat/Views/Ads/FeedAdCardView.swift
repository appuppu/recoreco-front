//
//  FeedAdCardView.swift
//  SugarBeat
//

import SwiftUI
import GoogleMobileAds

struct FeedAdCardView: View {
    @StateObject private var adManager = FeedAdManager.shared
    @State private var nativeAd: NativeAd?
    @State private var hasAttemptedLoad = false
    @State private var showPlaceholder = true

    var body: some View {
        Group {
            if let ad = nativeAd {
                NativeAdViewWrapper(nativeAd: ad)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onAppear {
                        print("🎵 [FeedAdCardView] Ad displayed")
                    }
            } else if showPlaceholder {
                // Placeholder while loading - auto-hide after timeout
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 400)
                    .padding(.horizontal, 16)
                    .overlay(
                        VStack {
                            ProgressView()
                                .tint(.white)
                        }
                    )
                    .onAppear {
                        print("🎵 [FeedAdCardView] Loading placeholder displayed")

                        // 5秒後にプレースホルダーを非表示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if nativeAd == nil {
                                print("🎵 [FeedAdCardView] Ad load timeout, hiding placeholder")
                                showPlaceholder = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            if !hasAttemptedLoad {
                hasAttemptedLoad = true
                loadAd()
            }
        }
        .onChange(of: adManager.loadedAds.count) { count in
            // 広告が読み込まれたら再試行
            if nativeAd == nil && count > 0 {
                loadAd()
            }
        }
    }

    private func loadAd() {
        Task { @MainActor in
            if let ad = adManager.getNextAd() {
                nativeAd = ad
                showPlaceholder = false
                print("🎵 [FeedAdCardView] Ad loaded from manager")
            } else {
                print("🎵 [FeedAdCardView] No ad available, waiting for manager to load")

                // 再試行（3秒後）
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if nativeAd == nil, let ad = adManager.getNextAd() {
                        nativeAd = ad
                        showPlaceholder = false
                        print("🎵 [FeedAdCardView] Ad loaded on retry")
                    }
                }
            }
        }
    }
}
