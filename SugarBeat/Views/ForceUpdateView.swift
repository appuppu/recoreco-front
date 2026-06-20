import SwiftUI

/// 強制アップデート画面
///
/// 閉じることができない全画面オーバーレイ。App Store の更新ページへ誘導する。
/// 現在のアプリが最低必須バージョン未満のときに `ContentView` の上に重ねて表示する。
struct ForceUpdateView: View {
    let appStoreUrl: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.white)

                VStack(spacing: 12) {
                    Text("アップデートが必要です")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("最新バージョンに更新してください。\nお使いのバージョンはサポートされなくなりました。")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button(action: openAppStore) {
                    Text("アップデート")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        // 全画面を覆い、下の画面を操作させない
        .interactiveDismissDisabled(true)
    }

    private func openAppStore() {
        guard let url = URL(string: appStoreUrl) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ForceUpdateView(appStoreUrl: "https://apps.apple.com/app/id6754846506")
}
