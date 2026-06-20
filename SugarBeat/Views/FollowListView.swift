import SwiftUI
import FirebaseAuth

enum FollowListType {
    case following
    case followers
}

struct FollowListView: View {
    let userId: String
    let listType: FollowListType
    @StateObject private var viewModel = FollowListViewModel()
    @Environment(\.dismiss) private var dismiss

    var title: String {
        listType == .following ? "フォロー" : "フォロワー"
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            } else if viewModel.users.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(title)がいません")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.users) { user in
                            if let rowUserId = user.id {
                                FollowListRow(
                                    user: user,
                                    onBlock: {
                                        Task {
                                            await viewModel.blockUser(userId: rowUserId)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadUsers(userId: userId, listType: listType)
        }
    }
}

struct FollowListRow: View {
    let user: User
    var onBlock: (() -> Void)? = nil
    @State private var showingBlockConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // プロフィール（画像・名前）をタップでユーザー詳細へ
            NavigationLink(destination: Group {
                if let userId = user.id {
                    UserProfileView(userId: userId)
                }
            }) {
                HStack(spacing: 12) {
                    // Profile image
                    AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image("recoreco")
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())

                    // User info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.username)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let isMutual = user.isMutual, isMutual {
                            Text("相互フォロー")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
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
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .contextMenu {
            if onBlock != nil {
                Button(role: .destructive) {
                    showingBlockConfirmation = true
                } label: {
                    Label("ブロック", systemImage: "hand.raised.fill")
                }
            }
        }
        .alert("ブロック確認", isPresented: $showingBlockConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック", role: .destructive) {
                onBlock?()
            }
        } message: {
            Text("\(user.username)さんをブロックしますか？\nブロックすると相手の投稿が表示されなくなり、フォロー関係も解除されます。")
        }
    }
}

@MainActor
class FollowListViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadUsers(userId: String, listType: FollowListType) async {
        isLoading = true
        errorMessage = nil

        do {
            switch listType {
            case .following:
                users = try await FirestoreFollowManager.shared.getFollowing(userId: userId)
            case .followers:
                users = try await FirestoreFollowManager.shared.getFollowers(userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func blockUser(userId: String) async {
        do {
            try await FirestoreBlockManager.shared.blockUser(userId: userId)
            // ブロックしたユーザーをリストから即座に除去
            users.removeAll { $0.id == userId }
        } catch {
            print("❌ Failed to block user from list: \(error)")
        }
    }
}
