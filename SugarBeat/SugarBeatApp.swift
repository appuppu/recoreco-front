import SwiftUI

@main
struct SugarBeatApp: App {
    @StateObject private var authManager = AuthManager()
    @ObservedObject private var musicKitManager = MusicKitManager.shared
    @State private var showLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.linear(duration: 2.0)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
    }
}
