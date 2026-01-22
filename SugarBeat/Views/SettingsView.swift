import SwiftUI
import FirebaseAuth

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showingEditProfile = false
    @State private var showingBlockedUsers = false
    @State private var showingOnboarding = false
    @State private var showingDeleteConfirmation = false
    @State private var showingUrlConfirmation = false
    @State private var urlToOpen: URL?
    @State private var urlTitle: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let user = viewModel.currentUser {
                    ScrollView {
                        VStack(spacing: 16) {

                            // Profile Edit Button
                            Button(action: {
                                showingEditProfile = true
                            }) {
                                HStack {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 16))
                                    Text("プロフィールを編集")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }

                            // Blocked Users Button
                            Button(action: {
                                showingBlockedUsers = true
                            }) {
                                HStack {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 16))
                                    Text("ブロックしたユーザー")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }

                            // Tutorial Button
                            Button(action: {
                                showingOnboarding = true
                            }) {
                                HStack {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 16))
                                    Text("使い方を見る")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }

                            // Contact Form Button
                            Button(action: {
                                urlTitle = "お問い合わせフォーム"
                                urlToOpen = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSeyy2ZI0cMqj7sEh19QRvCJknBiF9iBumr1Dqdt1o0tThCD9g/viewform?usp=header")
                                showingUrlConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 16))
                                    Text("お問い合わせ")
                                        .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }

                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.vertical, 8)

                            // Logout Button
                            Button(action: {
                                authManager.logout()
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                    Text("ログアウト")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }

                            // Delete Account Button
                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 16))
                                    Text("アカウントを削除")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }

                            // Terms and Privacy links
                            HStack(spacing: 20) {
                                Button(action: {
                                    urlTitle = "利用規約"
                                    urlToOpen = URL(string: "https://appuppu.github.io/docs/terms.html")
                                    showingUrlConfirmation = true
                                }) {
                                    Text("利用規約")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                        .underline()
                                }

                                Text("・")
                                    .foregroundColor(.white.opacity(0.5))

                                Button(action: {
                                    urlTitle = "プライバシーポリシー"
                                    urlToOpen = URL(string: "https://appuppu.github.io/docs/privacy.html")
                                    showingUrlConfirmation = true
                                }) {
                                    Text("プライバシーポリシー")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                        .underline()
                                }
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 32)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditProfile, onDismiss: {
            Task {
                await viewModel.loadCurrentUser()
            }
        }) {
            if let user = viewModel.currentUser {
                ProfileEditView(currentUser: user)
            }
        }
        .sheet(isPresented: $showingBlockedUsers) {
            BlockedUsersView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .alert("アカウント削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    await viewModel.deleteAccount()
                    authManager.logout()
                    dismiss()
                }
            }
        } message: {
            Text("アカウントを削除すると、すべてのデータが失われます。この操作は取り消せません。")
        }
        .alert("外部リンク", isPresented: $showingUrlConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("開く") {
                if let url = urlToOpen {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            if let url = urlToOpen {
                Text("\(urlTitle)のページに移動します。\n\n\(url.absoluteString)")
            }
        }
        .task {
            await viewModel.loadCurrentUser()
        }
    }
}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false

    func loadCurrentUser() async {
        isLoading = true

        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                print("❌ No current user ID")
                isLoading = false
                return
            }

            currentUser = try await FirestoreUserManager.shared.getUser(userId: currentUserId)
            print("✅ Loaded current user: \(currentUser?.username ?? "")")
        } catch {
            print("❌ Failed to load current user: \(error)")
        }

        isLoading = false
    }

    func deleteAccount() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        do {
            // Delete user data from Firestore
            try await FirestoreUserManager.shared.deleteUser(userId: currentUserId)

            // Delete Firebase Auth account
            try await Auth.auth().currentUser?.delete()

            print("✅ Account deleted successfully")
        } catch {
            print("❌ Failed to delete account: \(error)")
        }
    }
}
