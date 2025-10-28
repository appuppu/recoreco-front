import SwiftUI

struct BlockedUsersView: View {
    @StateObject private var viewModel = BlockedUsersViewModel()
    @Environment(\.dismiss) private var dismiss

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

                VStack(spacing: 0) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.blockedUsers.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "nosign")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.5))
                            Text("ブロックしているユーザーはいません")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.blockedUsers) { user in
                                    BlockedUserRow(
                                        user: user,
                                        onUnblock: {
                                            Task {
                                                await viewModel.unblockUser(userId: user.id)
                                            }
                                        }
                                    )

                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("ブロックリスト")
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
        .task {
            await viewModel.loadBlockedUsers()
        }
    }
}

struct BlockedUserRow: View {
    let user: User
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white.opacity(0.6))
                    )
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("@\(user.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button(action: onUnblock) {
                Text("ブロック解除")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

@MainActor
class BlockedUsersViewModel: ObservableObject {
    @Published var blockedUsers: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadBlockedUsers() async {
        isLoading = true
        errorMessage = nil

        do {
            blockedUsers = try await APIClient.shared.getBlockedUsers()
        } catch {
            errorMessage = "Failed to load blocked users: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func unblockUser(userId: Int64) async {
        do {
            try await APIClient.shared.unblockUser(userId: userId)
            blockedUsers.removeAll { $0.id == userId }
        } catch {
            errorMessage = "Failed to unblock user: \(error.localizedDescription)"
        }
    }
}
