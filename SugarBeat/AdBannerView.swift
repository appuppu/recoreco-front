import SwiftUI
import GoogleMobileAds

struct AdBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView()
        banner.adSize = AdSizeBanner
        banner.adUnitID = AdConfig.bannerAdUnitID
        banner.backgroundColor = .clear

        // WindowSceneからrootViewControllerを取得
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
            banner.load(Request())
        }

        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
    }
}
