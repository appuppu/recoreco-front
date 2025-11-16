import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds

@main
struct SugarBeatApp: App {
    @StateObject private var authManager = AuthManager()
    @ObservedObject private var musicKitManager = MusicKitManager.shared
    @State private var showLaunchScreen = true

    init() {
        // Google Mobile Ads SDKを初期化
        MobileAds.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main Content with Ad
                VStack(spacing: 0) {
                    // Main Content
                    if authManager.isAuthenticated {
                        if musicKitManager.isAuthorized {
                            ContentView()
                                .environmentObject(authManager)
                        } else {
                            MusicPermissionView()
                                .environmentObject(authManager)
                        }
                    } else {
                        LoginView()
                            .environmentObject(authManager)
                    }

                    // Banner Ad at the bottom (非表示: ログイン/登録画面、MusicPermission画面、テストモード)
                    if AdConfig.shouldShowAds && authManager.isAuthenticated && musicKitManager.isAuthorized {
                        AdBannerView()
                            .frame(height: 50)
                            .background(Color.black.opacity(0.9))
                    }
                }

                // Launch Screen
                if showLaunchScreen {
                    ZStack {
                        // Background gradient
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.8),
                                Color.red.opacity(0.6),
                                Color.black
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        // App Name
                        Text("おすすめの音楽を\n紹介しよう！")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .onAppear {
                // トラッキング許可をリクエスト
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    requestTrackingAuthorization()
                }

                // ローンチスクリーンを非表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.linear(duration: 2.0)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
    }

    private func requestTrackingAuthorization() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
