//
//  ProfileShareView.swift
//  SugarBeat
//
//  プロフィールURL共有画面
//

import SwiftUI

struct ProfileShareView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showingCopiedMessage = false

    var profileURL: URL? {
        guard let username = authManager.currentUser?.username else { return nil }
        return DeepLinkManager.generateProfileURL(username: username)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // メッセージ
                VStack(spacing: 16) {
                    Text("プロフィールをSNSで共有しよう！")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("プロフィール遷移URL")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }

                // URL表示とコピーボタン
                if let url = profileURL {
                    VStack(spacing: 16) {
                        // URL表示
                        Text(url.absoluteString)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal, 24)

                        // コピーボタン
                        Button(action: {
                            UIPasteboard.general.string = url.absoluteString
                            showingCopiedMessage = true

                            // コピーメッセージを2秒後に非表示
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showingCopiedMessage = false
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: showingCopiedMessage ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.system(size: 20))
                                Text(showingCopiedMessage ? "コピーしました！" : "URLをコピー")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: showingCopiedMessage ?
                                        [Color.green, Color.blue] :
                                        [Color.purple, Color.blue]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                        .disabled(showingCopiedMessage)
                    }
                }

                Spacer()

                // 閉じるボタン
                Button(action: {
                    dismiss()
                }) {
                    Text("閉じる")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ProfileShareView(authManager: AuthManager())
}
