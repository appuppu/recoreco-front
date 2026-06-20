import SwiftUI
import MusicKit

// MARK: - Vertical Swipe Feed View
struct VerticalSwipeFeedView: View {
    let posts: [Post]
    let isLoading: Bool
    let onLoadMore: () async -> Void
    let onRefresh: () async -> Void

    @State private var currentIndex: Int = 0
    @StateObject private var musicKit = MusicKitManager.shared
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var likeState = LikeStateManager.shared
    @StateObject private var commentState = CommentStateManager.shared

    var body: some View {
        ZStack {
            if posts.isEmpty && !isLoading {
                emptyState
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        SwipeFeedPostView(
                            post: post,
                            isCurrentPost: currentIndex == index
                        )
                        .tag(index)
                        .onAppear {
                            // Load more when approaching end
                            if index == posts.count - 2 {
                                Task {
                                    await onLoadMore()
                                }
                            }

                            // Auto-play when this post becomes visible
                            if currentIndex == index {
                                Task {
                                    await autoPlayPost(post)
                                }
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .ignoresSafeArea()
                .onChange(of: currentIndex) { newIndex in
                    // Stop previous track and play new one
                    musicKit.stopPreview()
                    playbackState.stopPlayback()

                    if newIndex < posts.count {
                        let newPost = posts[newIndex]
                        Task {
                            await autoPlayPost(newPost)
                        }
                    }
                }
            }

            // Loading indicator
            if isLoading && posts.isEmpty {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("投稿がありません")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func autoPlayPost(_ post: Post) async {
        guard let previewUrl = post.previewUrl else { return }

        do {
            let startTime = post.startTime ?? 0
            try await musicKit.playPreviewFromURL(previewUrl, startTime: startTime)
            playbackState.startPlayback(for: post.id ?? "", userId: post.userId, post: post, user: nil)
        } catch {
            print("❌ Auto-play failed: \(error)")
        }
    }
}

// MARK: - Swipe Feed Post View
struct SwipeFeedPostView: View {
    let post: Post
    let isCurrentPost: Bool

    @StateObject private var musicKit = MusicKitManager.shared
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var likeState = LikeStateManager.shared
    @StateObject private var commentState = CommentStateManager.shared
    @State private var user: User?
    @State private var showingComments = false
    @State private var showingUserProfile = false

    var body: some View {
        ZStack {
            // Background: Blurred artwork
            if let artworkUrl = post.artworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .blur(radius: 50)
                            .opacity(0.3)
                    }
                }
                .ignoresSafeArea()
            }

            // Dark overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Main artwork
                if let artworkUrl = post.artworkUrl, let url = URL(string: artworkUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: UIScreen.main.bounds.width * 0.85)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: UIScreen.main.bounds.width * 0.85, height: UIScreen.main.bounds.width * 0.85)
                                .overlay(
                                    ProgressView()
                                        .tint(.white)
                                )
                        }
                    }
                }

                // Song info and actions
                VStack(spacing: 16) {
                    // Track info
                    VStack(spacing: 8) {
                        if let trackName = post.trackName {
                            Text(trackName)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        if let artistName = post.artistName {
                            Text(artistName)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Comment
                    if let comment = post.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 32)
                    }

                    // User info (clickable)
                    if let user = user {
                        Button(action: {
                            showingUserProfile = true
                        }) {
                            HStack(spacing: 12) {
                                if let profileImageUrl = user.profileImageUrl, let url = URL(string: profileImageUrl) {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 32, height: 32)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                } else {
                                    Circle()
                                        .fill(Color.gray)
                                        .frame(width: 32, height: 32)
                                }

                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(20)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Action buttons
                    HStack(spacing: 32) {
                        // Play/Pause button
                        Button(action: {
                            Task {
                                if playbackState.isPlaying(post.id ?? "") {
                                    musicKit.stopPreview()
                                    playbackState.stopPlayback()
                                } else if let previewUrl = post.previewUrl {
                                    do {
                                        try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                                        playbackState.startPlayback(for: post.id ?? "", userId: post.userId, post: post, user: nil)
                                    } catch {
                                        print("Failed to play: \(error)")
                                    }
                                }
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: playbackState.isPlaying(post.id ?? "") ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white)
                                Text(playbackState.isPlaying(post.id ?? "") ? "停止" : "再生")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        // Like button
                        Button(action: {
                            Task {
                                if let postId = post.id {
                                    let wasLiked = likeState.isLiked(postId)
                                    likeState.toggleLike(postId: postId)

                                    do {
                                        if wasLiked {
                                            try await FirestoreLikeManager.shared.unlikePost(postId: postId)
                                        } else {
                                            try await FirestoreLikeManager.shared.likePost(postId: postId)
                                        }
                                    } catch {
                                        likeState.toggleLike(postId: postId)
                                        print("Failed to toggle like: \(error)")
                                    }
                                }
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: likeState.isLiked(post.id ?? "") ? "heart.fill" : "heart")
                                    .font(.system(size: 32))
                                    .foregroundColor(likeState.isLiked(post.id ?? "") ? .red : .white)
                                Text("\(likeState.getLikeCount(post.id ?? ""))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        // Comment button
                        Button(action: {
                            showingComments = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                Text("\(commentState.getCommentCount(post.id ?? ""))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .task {
            // Load user info
            do {
                user = try await FirestoreUserManager.shared.getUser(userId: post.userId)
            } catch {
                print("Failed to load user: \(error)")
            }
        }
        .sheet(isPresented: $showingComments) {
            if #available(iOS 16.4, *) {
                CommentsView(post: post)
                    .presentationBackground(Color.black)
                    .presentationCornerRadius(20)
            } else {
                CommentsView(post: post)
            }
        }
        .sheet(isPresented: $showingUserProfile) {
            if let user = user {
                if #available(iOS 16.4, *) {
                    NavigationStack {
                        UserProfileView(userId: user.id ?? "")
                    }
                    .presentationBackground(Color.black)
                } else {
                    NavigationStack {
                        UserProfileView(userId: user.id ?? "")
                    }
                }
            }
        }
    }
}
