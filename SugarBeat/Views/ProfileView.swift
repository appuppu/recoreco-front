import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingEditProfile = false
    @State private var showingBlockedUsers = false
    @State private var showingOnboarding = false
    @State private var showingDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationView {
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

                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let user = viewModel.currentUser {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Profile Image
                            if let imageUrl = user.profileImageUrl {
                                AsyncImage(url: URL(string: APIClient.shared.getFullImageURL(imageUrl) ?? "")) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(.white.opacity(0.5))
                                        )
                                }
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.5))
                                    )
                            }

                            // Display Name
                            Text(user.displayName)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            // Bio
                            if let bio = user.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            // Edit Profile Button
                            Button(action: {
                                showingEditProfile = true
                            }) {
                                Text("プロフィールを編集")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal, 32)
                            .padding(.top, 16)

                            // Public/Private Toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("公開アカウント")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(user.isPublic == true ? "すべてのユーザーがあなたの投稿を閲覧できます" : "相互フォローのユーザーのみ閲覧できます")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { user.isPublic ?? false },
                                    set: { newValue in
                                        Task {
                                            await viewModel.updatePublicStatus(isPublic: newValue)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal, 32)

                            // Blocked Users Button
                            Button(action: {
                                showingBlockedUsers = true
                            }) {
                                HStack {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 16))
                                    Text("ブロックしたユーザー")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }
                            .padding(.horizontal, 32)

                            // Tutorial Button
                            Button(action: {
                                showingOnboarding = true
                            }) {
                                HStack {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 16))
                                    Text("使い方を見る")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                            }
                            .padding(.horizontal, 32)

                            // Logout Button
                            Button(action: {
                                authManager.logout()
                            }) {
                                Text("ログアウト")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal, 32)

                            // Delete Account Button
                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                Text("アカウントを削除")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal, 32)
                            .padding(.bottom, 32)
                        }
                        .padding(.top, 32)
                    }
                } else {
                    Text("プロフィールの読み込みに失敗しました")
                        .foregroundColor(.white)
                }
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            })
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
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
        }
        .alert("アカウントの削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    do {
                        try await authManager.deleteAccount()
                    } catch {
                        print("❌ Failed to delete account: \(error)")
                    }
                }
            }
        } message: {
            Text("本当にアカウントを削除しますか？この操作は取り消せません。")
        }
        .task {
            await viewModel.loadCurrentUser()
        }
    }
}

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false

    func loadCurrentUser() async {
        isLoading = true

        do {
            guard let currentUserId = APIClient.shared.currentUserId else {
                print("❌ No current user ID")
                isLoading = false
                return
            }

            currentUser = try await APIClient.shared.getUser(id: currentUserId)
            print("✅ Loaded current user: \(currentUser?.displayName ?? "")")
        } catch {
            print("❌ Failed to load current user: \(error)")
        }

        isLoading = false
    }

    func updatePublicStatus(isPublic: Bool) async {
        guard let user = currentUser else { return }

        do {
            let request = APIClient.UpdateProfileRequest(
                displayName: user.displayName,
                profileImageUrl: user.profileImageUrl,
                bio: user.bio,
                isPublic: isPublic
            )
            currentUser = try await APIClient.shared.updateProfile(request: request)
            print("✅ Updated public status to: \(isPublic)")
        } catch {
            print("❌ Failed to update public status: \(error)")
            // Reload to revert the toggle
            await loadCurrentUser()
        }
    }
}
