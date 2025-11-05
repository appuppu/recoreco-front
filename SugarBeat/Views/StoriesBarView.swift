import SwiftUI

struct StoriesBarView: View {
    let allUserPosts: [UserPosts]
    let onUserTapped: (Int, UserPosts) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(allUserPosts.enumerated()), id: \.element.id) { index, userPosts in
                    StoryThumbnailView(
                        userPosts: userPosts,
                        isCurrentUser: index == 0
                    )
                    .onTapGesture {
                        onUserTapped(index, userPosts)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 110)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.25),
                    Color(red: 0.05, green: 0.05, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct StoryThumbnailView: View {
    let userPosts: UserPosts
    let isCurrentUser: Bool

    private var latestPost: Post? {
        userPosts.posts.first
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Gradient border for current user
                if isCurrentUser {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple,
                                    Color.blue
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                }

                // Artwork or placeholder
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
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                        case .failure:
                            placeholderView
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
            }

            Text(userPosts.user.displayName)
                .font(.caption2)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 70)
        }
    }

    private var placeholderView: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 70, height: 70)
            .overlay(
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            )
    }
}

#Preview {
    StoriesBarView(allUserPosts: [], onUserTapped: { _, _ in })
        .background(Color.black)
}
