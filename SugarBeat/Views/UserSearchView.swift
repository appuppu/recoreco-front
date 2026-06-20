import SwiftUI
import FirebaseAuth

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserSearchViewModel()
    @State private var searchQuery = ""

    var body: some View {
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
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom)

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
                        searchResultsList
                    }
                }
            }
            .navigationTitle("ユーザー検索")
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

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.users) { user in
                    if user.id != nil {
                        UserSearchRow(user: user)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

struct UserSearchRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            // プロフィール部分（画像・名前・bio）タップでユーザー詳細へ
            NavigationLink(destination: Group {
                if let userId = user.id {
                    UserProfileView(userId: userId)
                }
            }) {
                HStack(spacing: 12) {
                    // Profile image
                    AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image("recoreco")
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())

                    // User info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.username)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            // フォローボタン
            if let userId = user.id {
                FollowButton(userId: userId, compact: true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
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
            users = try await FirestoreUserManager.shared.searchUsers(query: query)
        } catch {
            errorMessage = "検索に失敗しました: \(error.localizedDescription)"
        }

        isSearching = false
    }
}
