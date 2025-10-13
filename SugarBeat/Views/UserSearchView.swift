import SwiftUI

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserSearchViewModel()
    @State private var searchQuery = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        TextField("ユーザー名で検索", text: $searchQuery)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.search)
                            .onSubmit {
                                Task {
                                    await viewModel.searchUsers(query: searchQuery)
                                }
                            }
                        if !searchQuery.isEmpty {
                            Button(action: {
                                searchQuery = ""
                                viewModel.users = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding()

                    // Search results
                    if viewModel.isSearching {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    } else if let errorMessage = viewModel.errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.red.opacity(0.7))
                            Text(errorMessage)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    } else if viewModel.users.isEmpty && !searchQuery.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.4))
                            Text("ユーザーが見つかりません")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                    } else if viewModel.users.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.4))
                            Text("ユーザーを検索")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.users) { user in
                                    UserSearchRow(
                                        user: user,
                                        onFollowToggle: {
                                            Task {
                                                if user.isFollowing == true {
                                                    await viewModel.unfollowUser(userId: user.id)
                                                } else {
                                                    await viewModel.followUser(userId: user.id)
                                                }
                                            }
                                        }
                                    )
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)

                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ユーザー検索")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

struct UserSearchRow: View {
    let user: User
    let onFollowToggle: () -> Void
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.2))
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("@\(user.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))

                if let isMutual = user.isMutual, isMutual {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("相互フォロー")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            // Follow button
            Button(action: {
                isProcessing = true
                onFollowToggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isProcessing = false
                }
            }) {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 80, height: 32)
                } else {
                    Text(user.isFollowing == true ? "フォロー中" : "フォロー")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(user.isFollowing == true ? .white : .black)
                        .frame(width: 80, height: 32)
                        .background(user.isFollowing == true ? Color.white.opacity(0.2) : Color.white)
                        .cornerRadius(16)
                }
            }
            .disabled(isProcessing)
        }
    }
}

@MainActor
class UserSearchViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    func searchUsers(query: String) async {
        guard !query.isEmpty else {
            users = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            users = try await APIClient.shared.searchUsers(query: query)
        } catch {
            errorMessage = "検索に失敗しました: \(error.localizedDescription)"
        }

        isSearching = false
    }

    func followUser(userId: Int64) async {
        do {
            try await APIClient.shared.followUser(userId: userId)
            // Update user in list
            if let index = users.firstIndex(where: { $0.id == userId }) {
                let updatedUser = users[index]
                // Create a new User instance with updated values
                users[index] = User(
                    id: updatedUser.id,
                    username: updatedUser.username,
                    email: updatedUser.email,
                    displayName: updatedUser.displayName,
                    profileImageUrl: updatedUser.profileImageUrl,
                    bio: updatedUser.bio,
                    createdAt: updatedUser.createdAt,
                    isFollowing: true,
                    isFollower: updatedUser.isFollower,
                    isMutual: updatedUser.isFollower == true ? true : false
                )
            }
        } catch {
            errorMessage = "フォローに失敗しました: \(error.localizedDescription)"
        }
    }

    func unfollowUser(userId: Int64) async {
        do {
            try await APIClient.shared.unfollowUser(userId: userId)
            // Update user in list
            if let index = users.firstIndex(where: { $0.id == userId }) {
                let updatedUser = users[index]
                users[index] = User(
                    id: updatedUser.id,
                    username: updatedUser.username,
                    email: updatedUser.email,
                    displayName: updatedUser.displayName,
                    profileImageUrl: updatedUser.profileImageUrl,
                    bio: updatedUser.bio,
                    createdAt: updatedUser.createdAt,
                    isFollowing: false,
                    isFollower: updatedUser.isFollower,
                    isMutual: false
                )
            }
        } catch {
            errorMessage = "アンフォローに失敗しました: \(error.localizedDescription)"
        }
    }
}
