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
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.orange.opacity(0.8),
                    Color.red.opacity(0.6),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                            if let userId = user.id {
                                NavigationLink(destination: UserProfileView(userId: userId)) {
                                    FollowListRow(user: user)
                                }
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

    var body: some View {
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
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    Text(user.username)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Mutual follow indicator
            if let isMutual = user.isMutual, isMutual {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    Text("相互")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
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
}
