import SwiftUI

struct UserProfileView: View {
    let userId: Int64
    @StateObject private var viewModel = UserProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var playbackStateManager = PlaybackStateManager.shared
    private let musicPlayer = MusicKitManager.shared
    @State private var showingActionSheet = false
    @State private var selectedPost: Post?
    @State private var showingPostActionSheet = false
    @State private var showingReportView = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let user = viewModel.user {
                    VStack(spacing: 20) {
                        // Profile Header
                        VStack(spacing: 12) {
                            // Profile Image
                            AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.6))
                                    )
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())

                            // Display Name
                            Text(user.displayName)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            // Username
                            Text(user.username)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))

                            // Follow counts
                            FollowCountsView(user: user)
                                .padding(.top, 8)

                            // Bio
                            if let bio = user.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.top, 4)
                            }

                            // Follow button (if not current user)
                            if let currentUserId = APIClient.shared.currentUserId, currentUserId != user.id {
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
                                        ZStack {
                                            if isFollowing {
                                                Color.white.opacity(0.2)
                                            } else {
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.purple,
                                                        Color.blue
                                                    ]),
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            }

                                            Text(isFollowing ? "フォロー中" : "フォロー")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        .frame(width: 200, height: 44)
                                        .cornerRadius(22)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                        .padding()
                        .padding(.top, 20)

                        // 3x3 Grid of posts (only visible for mutual follows or own profile)
                        let canViewPosts = (user.isMutual ?? false) ||
                                          (APIClient.shared.currentUserId == user.id)

                        if canViewPosts && !viewModel.posts.isEmpty {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2)
                            ], spacing: 2) {
                                ForEach(viewModel.posts) { post in
                                    ZStack {
                                        if let artworkUrl = post.artworkUrl,
                                           let url = URL(string: artworkUrl) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .empty:
                                                    Rectangle()
                                                        .fill(Color.gray.opacity(0.3))
                                                        .aspectRatio(1, contentMode: .fit)
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .aspectRatio(1, contentMode: .fill)
                                                case .failure:
                                                    Rectangle()
                                                        .fill(Color.gray.opacity(0.3))
                                                        .aspectRatio(1, contentMode: .fit)
                                                        .overlay(
                                                            Image(systemName: "music.note")
                                                                .foregroundColor(.white.opacity(0.6))
                                                        )
                                                @unknown default:
                                                    Rectangle()
                                                        .fill(Color.gray.opacity(0.3))
                                                        .aspectRatio(1, contentMode: .fit)
                                                }
                                            }
                                            .clipped()
                                        } else {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .aspectRatio(1, contentMode: .fit)
                                                .overlay(
                                                    Image(systemName: "music.note")
                                                        .foregroundColor(.white.opacity(0.6))
                                                )
                                        }

                                        // Play indicator overlay
                                        if playbackStateManager.currentlyPlayingPostId == post.id {
                                            ZStack {
                                                Color.black.opacity(0.3)

                                                WaveformView()
                                                    .frame(width: 40, height: 30)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Task {
                                            await togglePlayback(for: post)
                                        }
                                    }
                                    .onLongPressGesture {
                                        selectedPost = post
                                        showingPostActionSheet = true
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } else if !canViewPosts {
                            VStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.4))
                                Text("相互フォローで投稿を見ることができます")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.4))
                                Text("投稿がありません")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.top, 40)
                        }
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Text("エラー")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let currentUserId = APIClient.shared.currentUserId, currentUserId != userId {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingActionSheet = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(90))
                    }
                }
            }
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            Button("ブロック", role: .destructive) {
                Task {
                    await viewModel.blockUser(userId: userId)
                    dismiss()
                }
            }
            Button("キャンセル", role: .cancel) { }
        }
        .confirmationDialog("", isPresented: $showingPostActionSheet, titleVisibility: .hidden) {
            if let post = selectedPost {
                if let currentUserId = APIClient.shared.currentUserId, post.user.id == currentUserId {
                    Button("削除", role: .destructive) {
                        Task {
                            await viewModel.deletePost(postId: post.id)
                        }
                    }
                } else {
                    Button("報告", role: .destructive) {
                        showingReportView = true
                    }
                }
                Button("キャンセル", role: .cancel) {
                    selectedPost = nil
                }
            }
        }
        .sheet(isPresented: $showingReportView) {
            if let post = selectedPost {
                ReportPostView(post: post)
            }
        }
        .task {
            await viewModel.loadUser(userId: userId)
        }
    }

    private func togglePlayback(for post: Post) async {
        guard let previewUrl = post.previewUrl else { return }

        // If this post is currently playing, stop it
        if playbackStateManager.currentlyPlayingPostId == post.id {
            musicPlayer.stopPreview()
            playbackStateManager.stopPlayback()
            return
        }

        // Otherwise, play this post
        do {
            // Stop any currently playing post
            musicPlayer.stopPreview()

            // Small delay for smooth transition
            try? await Task.sleep(nanoseconds: 100_000_000)

            // Start playback
            try await musicPlayer.playPreviewFromURL(previewUrl, startTime: post.startTime)
            playbackStateManager.startPlayback(for: post.id)

            // Auto-stop after duration
            let duration = post.endTime - post.startTime
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if playbackStateManager.currentlyPlayingPostId == post.id {
                    musicPlayer.stopPreview()
                    playbackStateManager.stopPlayback()
                }
            }
        } catch {
            // Silently fail
        }
    }
}

// Helper view for follow counts
struct FollowCountsView: View {
    let user: User

    var body: some View {
        HStack(spacing: 20) {
            followingCountView
            followerCountView
        }
    }

    @ViewBuilder
    private var followingCountView: some View {
        let count = user.followingCount ?? 0
        let isMutual = user.isMutual ?? false
        let isOwnProfile = APIClient.shared.currentUserId == user.id

        if isMutual || isOwnProfile {
            NavigationLink(destination: FollowListView(userId: user.id, listType: .following)) {
                countLabel(count: count, label: "フォロー")
            }
        } else {
            countLabel(count: count, label: "フォロー")
        }
    }

    @ViewBuilder
    private var followerCountView: some View {
        let count = user.followerCount ?? 0
        let isMutual = user.isMutual ?? false
        let isOwnProfile = APIClient.shared.currentUserId == user.id

        if isMutual || isOwnProfile {
            NavigationLink(destination: FollowListView(userId: user.id, listType: .followers)) {
                countLabel(count: count, label: "フォロワー")
            }
        } else {
            countLabel(count: count, label: "フォロワー")
        }
    }

    private func countLabel(count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
