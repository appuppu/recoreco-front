import SwiftUI

struct UserProfileView: View {
    let userId: Int64
    @StateObject private var viewModel = UserProfileViewModel()

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let user = viewModel.user {
                VStack(spacing: 20) {
                    // Profile Header
                    VStack(spacing: 12) {
                        AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())

                        Text(user.displayName)
                            .font(.title)
                            .fontWeight(.bold)

                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let bio = user.bio {
                            Text(bio)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Follow button
                        if let isFollowing = user.isFollowing {
                            Button(action: {
                                Task {
                                    if isFollowing {
                                        await viewModel.unfollowUser(userId: userId)
                                    } else {
                                        await viewModel.followUser(userId: userId)
                                    }
                                }
                            }) {
                                Text(isFollowing ? "Unfollow" : "Follow")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 200, height: 44)
                                    .background(isFollowing ? Color.gray : Color.blue)
                                    .cornerRadius(22)
                            }
                        }
                    }
                    .padding()

                    Divider()

                    // Posts
                    Text("Posts")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.posts) { post in
                            UserPostRow(post: post)
                                .padding(.horizontal)
                        }
                    }
                }
            } else if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadUser(userId: userId)
        }
    }
}
