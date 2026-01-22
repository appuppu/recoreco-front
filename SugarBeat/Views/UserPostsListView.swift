import SwiftUI

struct UserPostsListView: View {
    let allUserPosts: [UserPosts]
    let unreadCounts: [String: Int]
    let onUserTapped: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dark background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // List container
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Header space (for safe area and balance)
                    Spacer()
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.15, green: 0.15, blue: 0.25),
                                    Color(red: 0.1, green: 0.1, blue: 0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // User posts list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(allUserPosts.enumerated()), id: \.element.id) { index, userPosts in
                                UserPostListRow(
                                    userPosts: userPosts,
                                    isCurrentUser: index == 0,
                                    unreadCount: userPosts.user.id.flatMap { unreadCounts[$0] } ?? 0
                                )
                                .onTapGesture {
                                    onUserTapped(index)
                                }

                                if index < allUserPosts.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                            }
                        }
                    }
                }
                .frame(width: UIScreen.main.bounds.width * 0.85)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.2),
                            Color.black
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()

                Spacer()
            }
        }
    }
}

struct UserPostListRow: View {
    let userPosts: UserPosts
    let isCurrentUser: Bool
    let unreadCount: Int

    private var latestPost: Post? {
        userPosts.posts.first
    }

    var body: some View {
        HStack(spacing: 12) {
            // Jacket image
            if let artworkUrl = latestPost?.artworkUrl,
               let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                    case .failure:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }

            // User info and comment
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(userPosts.user.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    if isCurrentUser {
                        Text("あなた")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple.opacity(0.6),
                                        Color.blue.opacity(0.6)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(4)
                    }

                    if unreadCount > 0 {
                        Text("新着\(unreadCount)件")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(4)
                    }
                }

                if let comment = latestPost?.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .padding(.top, 2)
                } else if let trackName = latestPost?.trackName {
                    Text(trackName)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.clear)
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            )
    }
}

#Preview {
    UserPostsListView(
        allUserPosts: [],
        unreadCounts: [:],
        onUserTapped: { _ in },
        onDismiss: {}
    )
}
