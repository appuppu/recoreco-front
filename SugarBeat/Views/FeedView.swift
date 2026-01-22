import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @Binding var postCreated: Bool

    var body: some View {
        let _ = print("🎯 FeedView body evaluated - isLoading: \(viewModel.isLoading), allUserPosts.count: \(viewModel.allUserPosts.count)")

        return Group {
            if viewModel.isLoading && viewModel.allUserPosts.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        print("🔄 FeedView: Showing loading state")
                    }
            } else if viewModel.allUserPosts.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))

                    Text("投稿がありません")
                        .font(.title2)
                        .foregroundColor(.white)

                    Text("フォローしているユーザーの投稿が\nここに表示されます")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    print("📭 FeedView: Showing empty state")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        Text("DEBUG: allUserPosts count = \(viewModel.allUserPosts.count)")
                            .foregroundColor(.green)
                            .onAppear {
                                print("📊 FeedView: ScrollView rendered with \(viewModel.allUserPosts.count) users")
                            }

                        ForEach(viewModel.allUserPosts) { userPosts in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("DEBUG: User = \(userPosts.user.username), Posts = \(userPosts.posts.count)")
                                    .foregroundColor(.yellow)
                                    .onAppear {
                                        print("👤 FeedView: Rendering user \(userPosts.user.username) with \(userPosts.posts.count) posts")
                                    }

                                // User header
                                HStack(spacing: 12) {
                                    // Profile image
                                    if let profileImageUrl = userPosts.user.profileImageUrl,
                                       let url = URL(string: profileImageUrl) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 40, height: 40)
                                                    .clipShape(Circle())
                                            default:
                                                Circle()
                                                    .fill(Color.gray)
                                                    .frame(width: 40, height: 40)
                                            }
                                        }
                                    } else {
                                        Circle()
                                            .fill(Color.gray)
                                            .frame(width: 40, height: 40)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(userPosts.user.displayName ?? userPosts.user.username)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text("@\(userPosts.user.username)")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal)

                                // Posts for this user
                                ForEach(userPosts.posts) { post in
                                    PostCard(post: post, user: userPosts.user)
                                        .onAppear {
                                            print("🎵 PostCard appeared for: \(post.musicTrackName ?? "Unknown")")
                                        }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.refreshFeed()
                }
            }
        }
        .background(Color.black)
        .task {
            await viewModel.loadFeed()
        }
        .onAppear {
            print("✅ FeedView.onAppear called")
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .onChange(of: postCreated) { created in
            if created {
                Task {
                    await viewModel.refreshFeed()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Foundation.Notification.Name.postCreated)) { _ in
            Task {
                await viewModel.refreshFeed()
            }
        }
    }
}

struct PostCard: View {
    let post: Post
    let user: User
    @StateObject private var likeState = LikeStateManager.shared
    @StateObject private var commentState = CommentStateManager.shared
    @StateObject private var playbackState = PlaybackStateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Artwork - Large display
            if let artworkUrl = post.musicArtworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onAppear {
                                print("🖼️ Image loaded successfully: \(artworkUrl)")
                            }
                    case .loading:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                            .onAppear {
                                print("⏳ Loading image: \(artworkUrl)")
                            }
                    case .failure(let error):
                        Rectangle()
                            .fill(Color.red.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onAppear {
                                print("❌ Image failed to load: \(error.localizedDescription)")
                            }
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Text("⚠️ No artwork URL")
                    .foregroundColor(.red)
                    .onAppear {
                        print("⚠️ Post has no artwork URL: \(post.id ?? "unknown")")
                    }
            }

            // Track Info
            VStack(alignment: .leading, spacing: 8) {
                if let trackName = post.musicTrackName {
                    Text(trackName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                if let artistName = post.musicArtistName {
                    Text(artistName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // Comment
            if let comment = post.comment, !comment.isEmpty {
                Text(comment)
                    .font(.body)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Action buttons
            HStack(spacing: 24) {
                // Play button
                Button(action: {
                    Task {
                        await playbackState.playTrack(
                            trackId: post.musicTrackId ?? "",
                            postId: post.id ?? ""
                        )
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: playbackState.currentlyPlayingPostId == post.id ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                        Text(playbackState.currentlyPlayingPostId == post.id ? "再生中" : "再生")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                // Like button
                Button(action: {
                    Task {
                        if let postId = post.id {
                            let isLiked = likeState.isLiked(postId: postId)
                            if isLiked {
                                await likeState.unlikePost(postId: postId)
                            } else {
                                await likeState.likePost(postId: postId)
                            }
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: likeState.isLiked(postId: post.id ?? "") ? "heart.fill" : "heart")
                            .foregroundColor(likeState.isLiked(postId: post.id ?? "") ? .red : .white)
                        Text("\(likeState.getLikeCount(postId: post.id ?? ""))")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Comment button
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(.white)
                    Text("\(commentState.getCommentCount(postId: post.id ?? ""))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}
