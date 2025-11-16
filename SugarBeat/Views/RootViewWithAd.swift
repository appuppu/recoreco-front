import SwiftUI

/// アプリ全体でバナー広告を表示するためのラッパービュー
struct RootViewWithAd<Content: View>: View {
    let content: Content
    let showAd: Bool

    init(showAd: Bool = true, @ViewBuilder content: () -> Content) {
        self.showAd = showAd
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // メインコンテンツ
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, (showAd && AdConfig.shouldShowAds) ? AdConfig.bannerHeight : 0)

                // バナー広告（最前面に配置）
                if showAd && AdConfig.shouldShowAds {
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
    }
}
