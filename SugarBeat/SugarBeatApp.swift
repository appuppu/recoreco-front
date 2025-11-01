import SwiftUI

@main
struct SugarBeatApp: App {
    @StateObject private var authManager = AuthManager()
    @ObservedObject private var musicKitManager = MusicKitManager.shared

    var body: some Scene {
        WindowGroup {
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
        }
    }
}
