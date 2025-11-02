import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        NavigationView {
            VStack {
                List(viewModel.users) { user in
                    NavigationLink(destination: UserProfileView(userId: user.id)) {
                        UserRow(user: user)
                    }
                }
                .searchable(text: $viewModel.searchQuery, prompt: "Search users")
                .onChange(of: viewModel.searchQuery) { _ in
                    viewModel.search()
                }
                .overlay {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if viewModel.users.isEmpty && !viewModel.searchQuery.isEmpty {
                        VStack {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No users found")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Search")
        }
    }
}

struct UserRow: View {
    let user: User

    var body: some View {
        HStack {
            AsyncImage(url: URL(string: APIClient.shared.getFullImageURL(user.profileImageUrl) ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: user.isPublic == true ? "network" : "network.badge.shield.half.filled")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text(user.displayName)
                        .font(.headline)
                }
            }

            Spacer()

            if let isMutual = user.isMutual, isMutual {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundColor(.blue)
            } else if let isFollowing = user.isFollowing, isFollowing {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}

#Preview {
    SearchView()
}
