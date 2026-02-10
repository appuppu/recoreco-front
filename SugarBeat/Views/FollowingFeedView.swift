import SwiftUI
import FirebaseAuth

/// フォロー中タブ - フォロー中チャンネルの最新投稿を表示（チャンネルごとに1投稿）
struct FollowingFeedView: View {
    @StateObject private var viewModel = FollowingFeedViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingLoginSheet = false
    @State private var selectedChannelType: ChannelType = .shared
    @State private var showingCompose42 = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                Color.black.ignoresSafeArea()

                if !authManager.isAuthenticated {
                    // 未ログイン状態
                    LoginRequiredView(showingLoginSheet: $showingLoginSheet, message: "フォロー中の投稿を見るには\nログインしてください")
                } else if viewModel.isLoading && viewModel.channelsWithPosts.isEmpty {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2.0)
                    }
                    .onAppear {
                        print("🔄 [FollowingFeedView] Initial loading ProgressView displayed")
                    }
                } else if let errorMessage = viewModel.errorMessage, viewModel.channelsWithPosts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red.opacity(0.7))
                        Text(errorMessage)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Button("再読み込み") {
                            Task {
                                await viewModel.loadFollowedChannelsPosts()
                            }
                        }
                        .foregroundColor(.purple)
                    }
                    .padding()
                } else if viewModel.channelsWithPosts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.4))
                        Text("フォロー中のチャンネルの\n投稿がありません")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Channel type switcher
                        HStack(spacing: 8) {
                            Button(action: {
                                print("🔘 [FollowingFeedView] User tapped '参加中の公開チャンネル' tab")
                                withAnimation {
                                    selectedChannelType = .shared
                                    viewModel.filterChannels(by: .shared)
                                }
                            }) {
                                Text("参加中の公開チャンネル")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(selectedChannelType == .shared ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedChannelType == .shared ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                                    .cornerRadius(8)
                            }

                            Button(action: {
                                print("🔘 [FollowingFeedView] User tapped '個人チャンネル' tab")
                                withAnimation {
                                    selectedChannelType = .personal
                                    viewModel.filterChannels(by: .personal)
                                }
                            }) {
                                Text("個人チャンネル")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(selectedChannelType == .personal ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedChannelType == .personal ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.black)

                        ZStack {
                            GeometryReader { geometry in
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                    ForEach(Array(viewModel.channelsWithPosts.enumerated()), id: \.element.channel.id) { index, item in
                                        if let latestPostId = item.channel.latestPostId {
                                            ChannelDiscoveryCard(
                                                channel: item.channel,
                                                postId: latestPostId
                                            )
                                            .padding(.vertical, 4)

                                            // チャンネル間の区切り線
                                            if index < viewModel.channelsWithPosts.count - 1 {
                                                Divider()
                                                    .background(Color.white.opacity(0.2))
                                                    .padding(.vertical, 4)
                                            }
                                        }

                                        // 2チャンネルごとに広告を表示
                                        if (index + 1) % 2 == 0 && AdConfig.shouldShowAds {
                                            FeedAdCardView()
                                                .id("following_ad_\(index)")
                                                .padding(.vertical, 8)
                                                .onAppear {
                                                    print("📢 [FollowingFeedView] Ad view appeared after channel index \(index)")
                                                }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                                .padding(.bottom, 100)
                            }
                            .scrollIndicators(.hidden)
                            .refreshable {
                                await viewModel.refreshChannels(channelType: selectedChannelType)
                            }
                        }
                    }
                    }
                }

                // Floating "私を構成する42枚" button
                Button {
                    showingCompose42 = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 16, weight: .semibold))
                        Text("私を構成する42枚")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.leading, 8)
                .padding(.bottom, 20) // Above tab bar
            }
            .navigationTitle("フォロー中/参加中と自分のチャンネル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .fullScreenCover(isPresented: $showingCompose42) {
                Compose42View()
                    .environmentObject(authManager)
            }
        }
        .task {
            print("🎯 [FollowingFeedView] .task executed - isAuthenticated: \(authManager.isAuthenticated), channelsWithPosts.isEmpty: \(viewModel.channelsWithPosts.isEmpty)")
            if viewModel.channelsWithPosts.isEmpty && authManager.isAuthenticated {
                print("🔄 [FollowingFeedView] Loading initial channels...")
                await viewModel.loadFollowedChannelsPosts(channelType: .shared)
            }
        }
        .onChange(of: authManager.isAuthenticated) { isAuthenticated in
            print("🎯 [FollowingFeedView] .onChange(isAuthenticated) - new value: \(isAuthenticated)")
            if isAuthenticated && viewModel.channelsWithPosts.isEmpty {
                Task {
                    await viewModel.loadFollowedChannelsPosts(channelType: .shared)
                }
            }
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            LoginView()
        }
    }
}

// MARK: - ViewModel
@MainActor
class FollowingFeedViewModel: ObservableObject {
    struct ChannelWithPost {
        let channel: Channel
        let post: Post?
    }

    @Published var channelsWithPosts: [ChannelWithPost] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var allChannelsWithPosts: [ChannelWithPost] = []

    init() {
        // 投稿完了通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("📥 [FollowingFeedViewModel] Received postCreated notification, reloading channels...")
                await self?.loadFollowedChannelsPosts()
            }
        }

        // チャンネル作成通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name("ChannelCreated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadFollowedChannelsPosts()
            }
        }

        // 投稿削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let postId = notification.userInfo?["postId"] as? String {
                Task { @MainActor in
                    await self?.loadFollowedChannelsPosts()
                }
            }
        }

        // ユーザーブロック通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.userBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let blockedUserId = notification.userInfo?["blockedUserId"] as? String {
                Task { @MainActor in
                    // ブロックされたユーザーのチャンネルを即座に削除
                    self?.allChannelsWithPosts.removeAll { $0.channel.userId == blockedUserId }
                    self?.channelsWithPosts.removeAll { $0.channel.userId == blockedUserId }
                    print("🚫 Removed blocked user's channels from following feed: \(blockedUserId)")
                }
            }
        }
    }

    func loadFollowedChannelsPosts(channelType: ChannelType = .shared) async {
        print("🔄 [FollowingFeedViewModel] loadFollowedChannelsPosts started - channelType: \(channelType.rawValue)")
        isLoading = true
        errorMessage = nil

        do {
            // 現在のユーザーIDを取得
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                isLoading = false
                throw FirestorePostError.notAuthenticated
            }
            print("✅ [FollowingFeedViewModel] Current userId: \(currentUserId)")

            // ブロック関連ユーザーリストを取得（双方向）
            let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []

            // フォロー中のチャンネルを取得
            var channels = try await FirestoreChannelManager.shared.getFollowedChannels(userId: currentUserId)
            print("✅ [FollowingFeedViewModel] Fetched \(channels.count) followed channels")

            // 自分のチャンネルも取得して追加
            let ownChannels = try await FirestoreChannelManager.shared.getUserChannels(userId: currentUserId)
            print("✅ [FollowingFeedViewModel] Fetched \(ownChannels.count) own channels")
            channels.append(contentsOf: ownChannels)

            // ブロック関連ユーザーのチャンネルを除外（双方向）
            channels = channels.filter { !blockedUserIds.contains($0.userId) }

            // 最新の投稿順にソート
            channels.sort { ($0.latestPostAt ?? Date.distantPast) > ($1.latestPostAt ?? Date.distantPast) }

            // Log channel types breakdown
            let sharedCount = channels.filter { $0.channelType == .shared }.count
            let personalCount = channels.filter { $0.channelType == .personal }.count
            print("✅ [FollowingFeedViewModel] Total channels: \(channels.count) (shared: \(sharedCount), personal: \(personalCount))")

            // Log personal channels details
            let personalChannels = channels.filter { $0.channelType == .personal }
            for channel in personalChannels {
                let latestPostDate = channel.latestPostAt?.formatted() ?? "No posts"
                print("📋 [FollowingFeedViewModel] Personal Channel: \(channel.name) | ID: \(channel.id ?? "nil") | Latest: \(latestPostDate)")
            }

            // チャンネルと投稿のペアを作成（全チャンネル）
            allChannelsWithPosts = channels.map { ChannelWithPost(channel: $0, post: nil) }

            // Filter by type
            filterChannels(by: channelType)

            print("📥 Following Feed: Loaded \(allChannelsWithPosts.count) total channels")
        } catch {
            errorMessage = "読み込みに失敗しました"
            print("❌ Following Feed: Failed to load channels: \(error)")
        }

        isLoading = false
    }

    func refreshChannels(channelType: ChannelType) async {
        // Refresh without setting isLoading to avoid double animation
        print("🔄 [FollowingFeedViewModel] refreshChannels called - forcing server fetch")
        errorMessage = nil

        do {
            // 現在のユーザーIDを取得
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                throw FirestorePostError.notAuthenticated
            }

            // ブロック関連ユーザーリストを取得（双方向）
            let blockedUserIds = (try? await FirestoreBlockManager.shared.getAllBlockRelatedUsers()) ?? []

            // フォロー中のチャンネルを取得（強制的にサーバーから）
            var channels = try await FirestoreChannelManager.shared.getFollowedChannels(userId: currentUserId, forceRefresh: true)

            // 自分のチャンネルも取得して追加
            let ownChannels = try await FirestoreChannelManager.shared.getUserChannels(userId: currentUserId, forceRefresh: true)
            channels.append(contentsOf: ownChannels)

            // ブロック関連ユーザーのチャンネルを除外（双方向）
            channels = channels.filter { !blockedUserIds.contains($0.userId) }

            // 最新の投稿順にソート
            channels.sort { ($0.latestPostAt ?? Date.distantPast) > ($1.latestPostAt ?? Date.distantPast) }

            // チャンネルと投稿のペアを作成（全チャンネル）
            allChannelsWithPosts = channels.map { ChannelWithPost(channel: $0, post: nil) }

            // Filter by type
            filterChannels(by: channelType)

            print("📥 Following Feed: Refreshed \(allChannelsWithPosts.count) total channels")
        } catch {
            errorMessage = "読み込みに失敗しました"
            print("❌ Following Feed: Failed to refresh channels: \(error)")
        }
    }

    func filterChannels(by channelType: ChannelType) {
        channelsWithPosts = allChannelsWithPosts.filter { $0.channel.channelType == channelType }
        print("🔍 [FollowingFeedViewModel] Filtered to \(channelsWithPosts.count) \(channelType.rawValue) channels")
    }
}

// MARK: - Following Post Card
struct FollowingPostCard: View {
    let channel: Channel
    let postId: String
    @StateObject private var viewModel = ChannelPostsViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var likeState = LikeStateManager.shared
    @StateObject private var commentState = CommentStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @State private var showingChannelDetail = false
    @State private var showingComments = false
    @State private var currentPostIndex: Int = 0
    @State private var channelOwner: User? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.posts.isEmpty {
                // Channel Header (clickable)
                Button(action: {
                    showingChannelDetail = true
                }) {
                    HStack(spacing: 12) {
                        // Channel thumbnail - use first post's artwork (updates dynamically when posts are deleted)
                        if let artworkUrl = viewModel.posts.first?.artworkUrl,
                           let url = URL(string: artworkUrl) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                }
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 50, height: 50)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("by @\(channelOwner?.username ?? "unknown")")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                    .background(Color.white.opacity(0.2))

                // Posts TabView for horizontal swipe
                TabView(selection: $currentPostIndex) {
                    ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                        // Post Content
                        VStack(alignment: .leading, spacing: 12) {
                            // Artwork
                            if let artworkUrl = post.artworkUrl, let url = URL(string: artworkUrl) {
                        ZStack {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .aspectRatio(1, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        )
                                }
                            }

                            // Loading indicator when playing
                            if musicKit.isLoadingPreview && playbackState.isPlaying(post.id ?? "") {
                                ZStack {
                                    Color.black.opacity(0.3)
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.5)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    // Track info
                    VStack(alignment: .leading, spacing: 4) {
                        if let trackName = post.trackName {
                            Text(trackName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        if let artistName = post.artistName {
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
                    HStack(spacing: 20) {
                        // Play button
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
                            HStack(spacing: 6) {
                                Image(systemName: playbackState.currentlyPlayingPostId == post.id ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 22))
                                Text(playbackState.currentlyPlayingPostId == post.id ? "停止" : "再生")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                        }

                        Spacer()

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
                            HStack(spacing: 4) {
                                Image(systemName: likeState.isLiked(post.id ?? "") ? "heart.fill" : "heart")
                                    .foregroundColor(likeState.isLiked(post.id ?? "") ? .red : .white)
                                Text("\(likeState.getLikeCount(post.id ?? ""))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }

                        // Comment button
                        Button(action: {
                            showingComments = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                    .foregroundColor(.white)
                                Text("\(commentState.getCommentCount(post.id ?? ""))")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                        }
                        .padding(16)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)
            } else if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
                }
                .frame(height: 300)
                .onAppear {
                    print("🔄 [FollowingFeedView] Channel posts loading ProgressView displayed")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            if let channelId = channel.id {
                await viewModel.loadChannelPosts(channelId: channelId, latestPostId: postId)
            }
            // Load channel owner info
            channelOwner = try? await FirestoreUserManager.shared.getUser(userId: channel.userId)
        }
        .sheet(isPresented: $showingChannelDetail) {
            if let channelId = channel.id {
                if #available(iOS 16.4, *) {
                    ChannelDetailView(channelId: channelId)
                        .presentationBackground(Color.black)
                        .presentationCornerRadius(20)
                } else {
                    ChannelDetailView(channelId: channelId)
                }
            }
        }
        .sheet(isPresented: $showingComments) {
            if currentPostIndex < viewModel.posts.count {
                if #available(iOS 16.4, *) {
                    CommentsView(post: viewModel.posts[currentPostIndex])
                        .presentationBackground(Color.black)
                        .presentationCornerRadius(20)
                } else {
                    CommentsView(post: viewModel.posts[currentPostIndex])
                }
            }
        }
    }
}
