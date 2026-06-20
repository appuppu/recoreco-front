import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds
import FirebaseCore

// MARK: - アプリ全体のテーマカラー設定
enum AppTheme {
    static let gradientStartHex = "cc208e"
    static let gradientEndHex = "6713d2"

    static var gradientStartColor: Color {
        Color(hex: gradientStartHex)
    }

    static var gradientEndColor: Color {
        Color(hex: gradientEndHex)
    }

    static var horizontalGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var verticalGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var tintColor: Color {
        gradientStartColor
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: 1
        )
    }
}

@main
struct SugarBeatApp: App {
    @StateObject private var authManager = AuthManager()
    @ObservedObject private var musicKitManager = MusicKitManager.shared
    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @State private var showLaunchScreen = true

    init() {
        // Firebase is configured in AuthManager.init() before any Firebase access

        // 画像キャッシュを拡張（AsyncImage は URLSession.shared = URLCache.shared を使う）。
        // プロフィール画像・アートワーク等が2回目以降ディスク/メモリから即表示される。
        let memoryCapacity = 100 * 1024 * 1024   // 100 MB（メモリ）
        let diskCapacity = 300 * 1024 * 1024     // 300 MB（ディスク）
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity)

        // Google Mobile Ads SDKを初期化
        #if DEBUG
        // テストデバイスIDを設定（シミュレータは自動的にテストデバイス扱い）
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [ "b9fc35b353577c6b43b3386d57b7c2ca" ]
        print("🎵 Test device ID configured for AdMob")
        #endif

        MobileAds.shared.start { status in
            print("🎵 Google Mobile Ads initialized: \(status.adapterStatusesByClassName)")

            // 初期化完了後にフィード広告をプリロード
            Task { @MainActor in
                FeedAdManager.shared.loadAds(count: 5)
                // インタースティシャル広告もプリロード
                InterstitialAdManager.shared.load()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main Content
                if authManager.isAuthenticated {
                    // Authenticated users need MusicKit authorization
                    if musicKitManager.isAuthorized {
                        ContentView()
                            .environmentObject(authManager)
                            .environmentObject(deepLinkManager)
                            .preferredColorScheme(.dark)
                    } else {
                        MusicPermissionView()
                            .environmentObject(authManager)
                            .preferredColorScheme(.dark)
                    }
                } else {
                    // Unauthenticated users can view discovery feed
                    ContentView()
                        .environmentObject(authManager)
                        .environmentObject(deepLinkManager)
                        .preferredColorScheme(.dark)
                }

                // Launch Screen
                if showLaunchScreen {
                    ZStack {
                        // Background - flowing artwork grid
                        FlowingArtworkBackground()

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
            .task {
                // ラウンチスクリーン表示中に背景アートワークの取得を先行開始する
                // （全てタブが表示されるのを待たずにロードしておく）
                await ArtworkBackgroundLoader.shared.loadIfNeeded()
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
            .onOpenURL { url in
                print("🔗 [SugarBeatApp] Received URL: \(url.absoluteString)")
                _ = deepLinkManager.handleUniversalLink(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                guard let url = userActivity.webpageURL else {
                    print("❌ [SugarBeatApp] No webpage URL in user activity")
                    return
                }
                print("🔗 [SugarBeatApp] Received Universal Link: \(url.absoluteString)")
                _ = deepLinkManager.handleUniversalLink(url)
            }
        }
    }

    private func requestTrackingAuthorization() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
