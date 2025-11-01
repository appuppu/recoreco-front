import SwiftUI

struct MusicPermissionView: View {
    @ObservedObject private var musicKitManager = MusicKitManager.shared
    @State private var hasRequestedPermission = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Music icon
                Image(systemName: "music.note.list")
                    .font(.system(size: 80))
                    .foregroundColor(.white)

                // Title
                Text("Apple Musicへのアクセスが必要です")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Description
                Text("SugarBeatは音楽を検索・共有するためにApple Musicへのアクセスが必要です")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    if !hasRequestedPermission {
                        // Request permission button
                        Button(action: {
                            Task {
                                hasRequestedPermission = true
                                await musicKitManager.requestAuthorization()
                            }
                        }) {
                            ZStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple,
                                        Color.blue
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )

                                Text("許可する")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(height: 56)
                            .cornerRadius(28)
                        }
                        .padding(.horizontal, 40)
                    } else if musicKitManager.authorizationStatus == .denied ||
                              musicKitManager.authorizationStatus == .restricted {
                        // Show settings button when permission was denied
                        VStack(spacing: 12) {
                            Text("権限が拒否されました")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            Text("設定アプリから「SugarBeat」のApple Musicへのアクセスを許可してください")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 30)

                            Button(action: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                ZStack {
                                    Color.white.opacity(0.2)

                                    Text("設定を開く")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .frame(height: 56)
                                .cornerRadius(28)
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            musicKitManager.checkAuthorization()
        }
    }
}
