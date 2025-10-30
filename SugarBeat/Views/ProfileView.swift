import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingEditProfile = false
    @State private var showingBlockedUsers = false
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
                                AsyncImage(url: URL(string: imageUrl)) { image in
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

                            // Username
                            Text("@\(user.username)")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))

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

                            // Logout Button
                            Button(action: {
                                authManager.logout()
                            }) {
                                Text("ログアウト")
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
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
}
