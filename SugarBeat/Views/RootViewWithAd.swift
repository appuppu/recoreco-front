import SwiftUI

/// アプリ全体でバナー広告を表示するためのラッパービュー
struct RootViewWithAd<Content: View>: View {
    let content: Content
    let showAd: Bool
    @StateObject private var screenshotMode = ScreenshotModeManager.shared

    init(showAd: Bool = true, @ViewBuilder content: () -> Content) {
        self.showAd = showAd
        self.content = content()
    }

    /// 広告を表示するかどうか（スクショモード時は非表示）
    private var shouldDisplayAd: Bool {
        let result = showAd && AdConfig.shouldShowAds && !screenshotMode.isScreenshotMode
        print("📺 Ad visibility check: showAd=\(showAd), shouldShowAds=\(AdConfig.shouldShowAds), isScreenshotMode=\(screenshotMode.isScreenshotMode) → shouldDisplayAd=\(result)")
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // メインコンテンツ
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, shouldDisplayAd ? AdConfig.bannerHeight : 0)

                // バナー広告（最前面に配置、スクショモード時は非表示）
                if shouldDisplayAd {
                    VStack {
                        Spacer()
                        AdBannerView()
                            .frame(height: AdConfig.bannerHeight)
                            .background(Color.black)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.keyboard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: screenshotMode.isScreenshotMode) { newValue in
            print("📸 Screenshot mode changed to: \(newValue)")
        }
    }
}
