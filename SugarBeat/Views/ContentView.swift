import SwiftUI
import MusicKit

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @State private var selectedTab = 0
    @State private var showingNotifications = false
    @State private var showingUserSearch = false
    @State private var showingLoginSheet = false
    @State private var showingDeepLinkedProfile = false
    @State private var deepLinkedUserId: String?
    @State private var unreadNotificationCount = 0
    @State private var lastNotificationFetchTime: Date?
    @State private var postCreated = false

    init() {
        // タブバーの背景色を固定（キーボード表示時も色が変わらないように）
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        let _ = print("🏠 ContentView body evaluated - selectedTab: \(selectedTab)")

        ZStack {
            TabView(selection: $selectedTab) {
                // 発見タブ（ホーム）
                DiscoveryView()
                    .tabItem {
                        Image(systemName: "safari")
                        Text("すべて")
                    }
                    .tag(0)

                // フォロー中タブ
                FollowingFeedView()
                    .tabItem {
                        Image(systemName: "person.2.fill")
                        Text("フォロー中")
                    }
                    .tag(1)

                // 投稿タブ
                NavigationStack {
                    if authManager.isAuthenticated {
                        CreatePostView(postCreated: $postCreated)
                            .onAppear {
                                print("🔍 [ContentView] Post tab (tag:2) appeared - CreatePostView is being displayed")
                            }
                    } else {
                        LoginRequiredView(showingLoginSheet: $showingLoginSheet)
                            .navigationTitle("投稿")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(Color.black, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                }
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("投稿")
                }
                .tag(2)

                // 通知タブ
                NavigationStack {
                    if authManager.isAuthenticated {
                        NotificationsView()
                            .navigationTitle("通知")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(Color.black, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    } else {
                        LoginRequiredView(showingLoginSheet: $showingLoginSheet)
                            .navigationTitle("通知")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(Color.black, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                }
                .tabItem {
                    Image(systemName: "bell.fill")
                    Text("通知")
                }
                .badge(unreadNotificationCount > 0 ? unreadNotificationCount : 0)
                .tag(3)

                // プロフィールタブ
                if authManager.isAuthenticated {
                    MyProfileView()
                        .environmentObject(authManager)
                        .tabItem {
                            Image(systemName: "person.fill")
                            Text("プロフィール")
                        }
                        .tag(4)
                } else {
                    NavigationStack {
                        LoginRequiredView(showingLoginSheet: $showingLoginSheet)
                            .navigationTitle("プロフィール")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(Color.black, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("プロフィール")
                    }
                    .tag(4)
                }
            }
            .tint(.white)
            .toolbar(screenshotMode.isScreenshotMode ? .hidden : .visible, for: .tabBar)
            .toolbarBackground(.black, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        let horizontalTranslation = value.translation.width
                        if horizontalTranslation < -50 {
                            // 左にスワイプ（次のタブへ）
                            if selectedTab < 4 {
                                selectedTab += 1
                            }
                        } else if horizontalTranslation > 50 {
                            // 右にスワイプ（前のタブへ）
                            if selectedTab > 0 {
                                selectedTab -= 1
                            }
                        }
                    }
            )
            .onAppear {
                print("🎯 ContentView: TabView appeared")
            }
            .onChange(of: postCreated) { created in
                if created {
                    // 投稿成功後、フォロー中と自分タブに遷移
                    selectedTab = 1
                    // フラグをリセット
                    postCreated = false
                }
            }
        }
        .onAppear {
            print("✅ ContentView: Root ZStack appeared")
        }
        .sheet(isPresented: $showingNotifications, onDismiss: {
            Task {
                await loadUnreadNotificationCount(forceRefresh: true)
            }
        }) {
            if #available(iOS 16.4, *) {
                NotificationsView()
                    .presentationBackground(Color.clear)
                    .background(Color.black)
            } else {
                NotificationsView()
                    .background(Color.black)
            }
        }
        .sheet(isPresented: $showingUserSearch) {
            if #available(iOS 16.4, *) {
                UserSearchView()
                    .presentationBackground(Color.clear)
                    .background(Color.black)
            } else {
                UserSearchView()
                    .background(Color.black)
            }
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            if #available(iOS 16.4, *) {
                LoginView()
                    .presentationBackground(Color.clear)
                    .background(Color.black)
            } else {
                LoginView()
                    .background(Color.black)
            }
        }
        .task {
            if authManager.isAuthenticated {
                await loadUnreadNotificationCount(forceRefresh: true)
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if authManager.isAuthenticated {
                Task {
                    await loadUnreadNotificationCount()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Foundation.Notification.Name("ReloadUnreadCounts"))) { _ in
            Task {
                await loadUnreadNotificationCount(forceRefresh: true)
            }
        }
        .onChange(of: postCreated) { created in
            if created {
                // フィード更新通知
                NotificationCenter.default.post(name: Foundation.Notification.Name.postCreated, object: nil)
            }
        }
        .onChange(of: deepLinkManager.pendingProfileUsername) { username in
            guard let username = username else { return }
            print("🔗 [ContentView] Handling deep link for username: \(username)")

            Task {
                await handleDeepLinkedProfile(username: username)
            }
        }
        .fullScreenCover(isPresented: $showingDeepLinkedProfile, onDismiss: {
            deepLinkedUserId = nil
            deepLinkManager.clearPendingLink()
        }) {
            if let userId = deepLinkedUserId {
                UserProfileView(userId: userId)
                    .environmentObject(authManager)
            }
        }
        .alert("エラー", isPresented: $deepLinkManager.showingDeepLinkError) {
            Button("OK", role: .cancel) {
                deepLinkManager.clearPendingLink()
            }
        } message: {
            Text(deepLinkManager.deepLinkErrorMessage ?? "不明なエラーが発生しました")
        }
    }

    private func handleDeepLinkedProfile(username: String) async {
        do {
            // ユーザー名からユーザーIDを取得
            guard let user = try await FirestoreUserManager.shared.getUserByUsername(username: username) else {
                print("❌ [ContentView] User not found for username: \(username)")
                deepLinkManager.deepLinkErrorMessage = "ユーザーが見つかりませんでした"
                deepLinkManager.showingDeepLinkError = true
                deepLinkManager.clearPendingLink()
                return
            }

            guard let userId = user.id else {
                print("❌ [ContentView] User has no ID: \(username)")
                deepLinkManager.deepLinkErrorMessage = "ユーザー情報が不正です"
                deepLinkManager.showingDeepLinkError = true
                deepLinkManager.clearPendingLink()
                return
            }

            // ブロックチェック
            if authManager.isAuthenticated {
                let isBlocked = try await FirestoreBlockManager.shared.isUserBlocked(userId: userId)
                if isBlocked {
                    print("🚫 [ContentView] User is blocked: \(username)")
                    deepLinkManager.deepLinkErrorMessage = "このユーザーは表示できません"
                    deepLinkManager.showingDeepLinkError = true
                    deepLinkManager.clearPendingLink()
                    return
                }
            }

            print("✅ [ContentView] Opening profile for user: \(username) (ID: \(userId))")
            deepLinkedUserId = userId
            showingDeepLinkedProfile = true

        } catch {
            print("❌ [ContentView] Error loading user: \(error)")
            deepLinkManager.deepLinkErrorMessage = "ユーザー情報の取得に失敗しました"
            deepLinkManager.showingDeepLinkError = true
            deepLinkManager.clearPendingLink()
        }
    }

    private func loadUnreadNotificationCount(forceRefresh: Bool = false) async {
        guard authManager.isAuthenticated else {
            unreadNotificationCount = 0
            return
        }

        do {
            let count = try await FirestoreNotificationManager.shared.getCurrentUserUnreadCount()
            unreadNotificationCount = count
        } catch {
            print("❌ Failed to load unread notification count: \(error)")
            unreadNotificationCount = 0
        }
    }
}

// ログインが必要な画面
struct LoginRequiredView: View {
    @Binding var showingLoginSheet: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.6))

                Text("ログインが必要です")
                    .font(.title2)
                    .foregroundColor(.white)

                Text("プロフィールを表示するには\nログインしてください")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Button(action: {
                    showingLoginSheet = true
                }) {
                    Text("ログイン")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: 200)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.orange, Color.red]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                .padding(.top)
            }
        }
    }
}

// MARK: - FeedView
struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @Binding var postCreated: Bool

    var body: some View {
        let _ = print("🎯 FeedView body evaluated - isLoading: \(viewModel.isLoading), allUserPosts.count: \(viewModel.allUserPosts.count)")

        Group {
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
                                            print("🎵 PostCard appeared for: \(post.trackName ?? "Unknown")")
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
    @StateObject private var musicKit = MusicKitManager.shared
    @State private var showingLoginPrompt = false
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Artwork - Large display
            if let artworkUrl = post.artworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onAppear {
                                print("🖼️ Image loaded successfully: \(artworkUrl)")
                            }
                    } else if phase.error != nil {
                        Rectangle()
                            .fill(Color.red.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onAppear {
                                print("❌ Image failed to load")
                            }
                    } else {
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
            HStack(spacing: 24) {
                // Play button
                Button(action: {
                    Task {
                        if playbackState.isPlaying(post.id ?? "") {
                            // Stop playback
                            musicKit.stopPreview()
                            playbackState.stopPlayback()
                        } else if let previewUrl = post.previewUrl {
                            // Start playback
                            do {
                                try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                                playbackState.startPlayback(for: post.id ?? "", userId: post.userId, post: post, user: user)
                            } catch {
                                print("❌ Failed to play preview: \(error)")
                            }
                        }
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
                    if !authManager.isAuthenticated {
                        showingLoginPrompt = true
                        return
                    }
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
                                // Revert on error
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
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Comment button
                Button(action: {
                    if !authManager.isAuthenticated {
                        showingLoginPrompt = true
                        return
                    }
                    // TODO: Navigate to comments view
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundColor(.white)
                        Text("\(commentState.getCommentCount(post.id ?? ""))")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .fullScreenCover(isPresented: $showingLoginPrompt) {
            LoginView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading && viewModel.channels.isEmpty {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2.0)
                    }
                    .onAppear {
                        print("🔄 [DiscoveryView] Initial loading ProgressView displayed")
                    }
                } else if !viewModel.channels.isEmpty {
                    ZStack {
                        GeometryReader { geometry in
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(viewModel.channels.enumerated()), id: \.element.id) { index, channel in
                                        ChannelDiscoveryCard(
                                            channel: channel,
                                            postId: channel.latestPostId ?? ""
                                        )
                                        .padding(.vertical, 4)

                                        // チャンネル間の区切り線
                                        if index < viewModel.channels.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.2))
                                                .padding(.vertical, 4)
                                        }

                                        // 2チャンネルごとに広告を表示
                                        if (index + 1) % 2 == 0 && AdConfig.shouldShowAds {
                                            FeedAdCardView()
                                                .id("discovery_ad_\(index)")
                                                .padding(.vertical, 8)
                                                .onAppear {
                                                    print("📢 [DiscoveryView] Ad view appeared after channel index \(index)")
                                                }
                                        }
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 100)
                            }
                            .scrollIndicators(.hidden)
                            .refreshable {
                                await viewModel.refreshChannels()
                            }
                        }
                    }
                }
            }
            .navigationTitle("すべてのチャンネル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await viewModel.loadChannels()
        }
    }
}

struct ChannelDiscoveryCard: View {
    let channel: Channel
    let postId: String
    @StateObject private var viewModel = ChannelPostsViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var likeState = LikeStateManager.shared
    @State private var channelOwner: User? = nil  // Channel owner info
    @StateObject private var commentState = CommentStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @EnvironmentObject var authManager: AuthManager
    @State private var showingChannelDetail = false
    @State private var showingUserProfile = false
    @State private var showingComments = false
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false
    @State private var currentPostIndex: Int = 0

    private var isOwnChannel: Bool {
        guard let currentUserId = authManager.currentUser?.id else { return false }
        return channel.userId == currentUserId
    }

    private var isFollowing: Bool {
        channel.isFollowing ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.posts.isEmpty {
                channelHeaderView

                Divider()
                    .background(Color.white.opacity(0.2))

                // Posts TabView for horizontal swipe (max 4 posts + "View Channel" button)
                GeometryReader { geometry in
                    let cardHeight = geometry.size.width // Square aspect ratio
                    let hasMoreThanFour = viewModel.posts.count > 4
                    let displayCount = hasMoreThanFour ? 5 : min(viewModel.posts.count, 4)

                    VStack(spacing: 4) {
                        TabView(selection: $currentPostIndex) {
                            // Show first 4 posts
                            ForEach(Array(viewModel.posts.prefix(4).enumerated()), id: \.element.id) { index, post in
                                ChannelPostCardGrid(
                                    post: post,
                                    channelName: channel.name,
                                    showingLoginPrompt: $showingLoginPrompt
                                )
                                .environmentObject(authManager)
                                .frame(width: geometry.size.width, height: cardHeight)
                                .tag(index)
                            }

                            // Show "View Channel" button as 5th item if there are more than 4 posts
                            if hasMoreThanFour {
                                Button(action: {
                                    showingChannelDetail = true
                                }) {
                                    ZStack {
                                        // Background - use latest post artwork if available
                                        if let latestPost = viewModel.posts.first,
                                           let artworkUrl = latestPost.artworkUrl,
                                           let url = URL(string: artworkUrl) {
                                            AsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .blur(radius: 10)
                                                        .overlay(Color.black.opacity(0.6))
                                                } else {
                                                    Color.black.opacity(0.8)
                                                }
                                            }
                                        } else {
                                            Color.black.opacity(0.8)
                                        }

                                        VStack(spacing: 16) {
                                            Image(systemName: "music.note.house.fill")
                                                .font(.system(size: 60))
                                                .foregroundColor(.white)

                                            Text("チャンネルへ")
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)

                                            Text("+\(viewModel.posts.count - 4) 件の投稿")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(width: geometry.size.width, height: cardHeight)
                                .tag(4)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: cardHeight)

                        // Dot indicator
                        if displayCount > 1 {
                            HStack(spacing: 8) {
                                ForEach(0..<displayCount, id: \.self) { index in
                                    Circle()
                                        .fill(currentPostIndex == index ? Color.white : Color.white.opacity(0.3))
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(height: UIScreen.main.bounds.width + 20)
            } else if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
                }
                .frame(height: 300)
                .onAppear {
                    print("🔄 [ChannelDiscoveryCard] Channel posts loading ProgressView displayed for channel: \(channel.id ?? "unknown")")
                }
            }
        }
        .task(id: postId) {
            if let channelId = channel.id {
                await viewModel.loadChannelPosts(channelId: channelId, latestPostId: postId, forceRefresh: true)
            }
            // Load channel owner info
            channelOwner = try? await FirestoreUserManager.shared.getUser(userId: channel.userId)
        }
        .fullScreenCover(isPresented: $showingChannelDetail) {
            if let channelId = channel.id {
                ChannelDetailView(channelId: channelId)
            }
        }
        .fullScreenCover(isPresented: $showingUserProfile) {
            UserProfileView(userId: channel.userId)
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
        .alert("ログインが必要です", isPresented: $showingLoginPrompt) {
            Button("キャンセル", role: .cancel) {}
            Button("ログイン") {
                showingLoginSheet = true
            }
        } message: {
            Text("この機能を利用するにはログインが必要です")
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            LoginView()
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private var channelThumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Channel artwork - try channel's artworkUrl first, fallback to first post's artwork
            let artworkUrl = channel.latestPostArtworkUrl ?? viewModel.posts.first?.artworkUrl

            if let artworkUrlString = artworkUrl,
               let url = URL(string: artworkUrlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if phase.error != nil {
                        // Loading failed, show placeholder
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    } else {
                        // Loading in progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.5))
                    )
            }

            // Profile icon overlay
            profileOverlayButton
        }
    }

    @ViewBuilder
    private var profileOverlayButton: some View {
        Button(action: {
            if !authManager.isAuthenticated {
                showingLoginPrompt = true
                return
            }
            showingUserProfile = true
        }) {
            if let profileImageUrl = channelOwner?.profileImageUrl,
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    } else if phase.error != nil {
                        // Error loading image
                        profilePlaceholder
                    } else {
                        // Loading in progress
                        profilePlaceholder
                    }
                }
            } else {
                profilePlaceholder
            }
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: 3, y: 3)
    }

    @ViewBuilder
    private var profilePlaceholder: some View {
        Image("recoreco")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black, lineWidth: 2))
    }

    @ViewBuilder
    private var channelHeaderView: some View {
        Button(action: {
            showingChannelDetail = true
        }) {
            HStack(spacing: 12) {
                channelThumbnailView

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text(channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 4) {
                        Text("by")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            showingUserProfile = true
                        }) {
                            Text("@\(channelOwner?.username ?? "unknown")")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .underline()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()

                channelActionButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var channelActionButton: some View {
        Button(action: {
            showingChannelDetail = true
        }) {
            Text("チャンネルへ")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}

struct FollowButton: View {
    let channelId: String
    @State var isFollowing: Bool
    @State private var isProcessing = false
    @State private var showingLoginPrompt = false
    @State private var showingLoginAlert = false
    var buttonText: String = "フォロー"
    var followingText: String = "フォロー中"
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if isFollowing {
                // Following status display (not clickable)
                Text(followingText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.5))
                    .clipShape(Capsule())
            } else {
                // Follow button (clickable)
                Button(action: {
                    if !authManager.isAuthenticated {
                        showingLoginAlert = true
                        return
                    }
                    Task {
                        isProcessing = true
                        defer { isProcessing = false }

                        do {
                            try await FirestoreChannelManager.shared.followChannel(channelId: channelId)
                            isFollowing = true

                            // チャンネル情報の再読み込みを通知
                            NotificationCenter.default.post(
                                name: Foundation.Notification.Name("ChannelFollowed"),
                                object: nil,
                                userInfo: ["channelId": channelId]
                            )
                        } catch {
                            print("Failed to follow: \(error)")
                        }
                    }
                }) {
                    Text(buttonText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.orange, Color.red]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .disabled(isProcessing)
                .opacity(isProcessing ? 0.6 : 1.0)
            }
        }
        .alert("ログインが必要です", isPresented: $showingLoginAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("ログイン") {
                showingLoginPrompt = true
            }
        } message: {
            Text("この機能を利用するにはログインが必要です")
        }
        .fullScreenCover(isPresented: $showingLoginPrompt) {
            LoginView()
        }
    }
}

// MARK: - ViewModels

@MainActor
class DiscoveryViewModel: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var isLoading = false

    init() {
        // Listen for user block notifications
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.userBlocked,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let blockedUserId = notification.userInfo?["blockedUserId"] as? String {
                Task { @MainActor in
                    self?.channels.removeAll { $0.userId == blockedUserId }
                    print("🚫 Removed blocked user's channels from discovery: \(blockedUserId)")
                }
            }
        }
    }

    func loadChannels() async {
        isLoading = true
        defer { isLoading = false }

        do {
            channels = try await FirestorePostManager.shared.getDiscoveryChannels(limit: 20)
        } catch {
            print("❌ Failed to load channels: \(error)")
        }
    }

    func refreshChannels() async {
        // Refresh without setting isLoading to avoid double animation
        print("🔄 [DiscoveryViewModel] refreshChannels called")
        do {
            channels = try await FirestorePostManager.shared.getDiscoveryChannels(limit: 20)
            print("✅ [DiscoveryViewModel] Refreshed \(channels.count) channels")
        } catch {
            print("❌ Failed to refresh channels: \(error)")
        }
    }
}

@MainActor
class PostLoader: ObservableObject {
    @Published var post: Post?
    @Published var isLoading = false

    func loadPost(postId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            post = try await FirestorePostManager.shared.getPost(postId: postId)

            // Update like and comment state
            if let post = post, let id = post.id {
                LikeStateManager.shared.updateFromServer(
                    postId: id,
                    isLiked: post.isLiked ?? false,
                    count: post.likeCount
                )
                CommentStateManager.shared.updateFromServer(
                    postId: id,
                    count: post.commentCount
                )
            }
        } catch {
            print("❌ Failed to load post: \(error)")
        }
    }
}
import SwiftUI

struct ChannelDetailView: View {
    let channelId: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = ChannelDetailViewModel()
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false
    @State private var showingLoginAlert = false
    @State private var showingUserProfile = false
    @State private var showingCreatePost = false
    @State private var showingChannelMenu = false
    @State private var showingDeleteConfirmation = false

    private var isOwnChannel: Bool {
        guard let currentUserId = authManager.currentUser?.id else {
            print("⚠️ [ChannelDetailView] isOwnChannel: No current user")
            return false
        }
        let result = viewModel.channel?.userId == currentUserId
        print("🔍 [ChannelDetailView] isOwnChannel: \(result), currentUserId: \(currentUserId), channelUserId: \(viewModel.channel?.userId ?? "nil")")
        return result
    }

    private var customNavigationBar: some View {
        HStack {
            // Close button
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Title
            if let channel = viewModel.channel {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text(channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 4) {
                        Text("by @\(viewModel.channelOwner?.username ?? "unknown")")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text("・")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                        Text("\(channel.followerCount ?? 0) フォロワー")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("チャンネル詳細")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()

            // Trailing buttons
            HStack(spacing: 12) {
                // Show plus button only for own channel
                if isOwnChannel {
                    Button(action: {
                        print("✅ [ChannelDetailView] Plus button tapped, showingCreatePost = true")
                        showingCreatePost = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                }

                // More actions button
                Button(action: {
                    if !authManager.isAuthenticated {
                        showingLoginAlert = true
                        return
                    }
                    showingChannelMenu = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Color.black.opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .padding(.top, safeAreaInsets.top)
    }

    private var safeAreaInsets: UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets
        }
        return UIEdgeInsets()
    }

    @ViewBuilder
    private var mainContent: some View {
        let _ = print("📐 [ChannelDetailView] mainContent evaluated - isLoading: \(viewModel.isLoading), posts.count: \(viewModel.posts.count)")

        if viewModel.isLoading {
            VStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2.0)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                print("🔄 [ChannelDetailView] Loading channel info ProgressView displayed")
            }
        } else if let channel = viewModel.channel {
            // Posts list (scrollable)
            if viewModel.isLoadingPosts {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    print("🔄 [ChannelDetailView] Loading posts ProgressView displayed")
                }
            } else if viewModel.posts.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.4))
                        Text("まだ投稿がありません")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // フォローボタン（フォローしていない場合のみ表示）
                        if !isOwnChannel && !(channel.isFollowing ?? false) {
                            VStack(spacing: 0) {
                                FollowButton(
                                    channelId: channelId,
                                    isFollowing: channel.isFollowing ?? false,
                                    buttonText: "チャンネルをフォローする"
                                )
                                .padding(.vertical, 12)

                                Divider()
                                    .background(Color.white.opacity(0.2))
                            }
                        }

                        ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                            ChannelPostCard(
                                post: post,
                                showingLoginPrompt: $showingLoginPrompt,
                                channelName: channel.name
                            )

                            // 2投稿ごとに広告を表示
                            if (index + 1) % 2 == 0 && AdConfig.shouldShowAds {
                                FeedAdCardView()
                                    .id("channel_ad_\(index)")
                                    .padding(.vertical, 8)
                                    .onAppear {
                                        print("📢 [ChannelDetailView] Ad view appeared after post index \(index)")
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                    .onAppear {
                        print("📐 [ChannelDetailView] ScrollView LazyVStack appeared with \(viewModel.posts.count) posts")
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    print("📐 [ChannelDetailView] ScrollView appeared")
                }
                .refreshable {
                    await viewModel.loadPosts(channelId: channelId)
                }
            }
        } else {
            VStack {
                Spacer()
                Text("チャンネルが見つかりません")
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        let _ = print("📐 [ChannelDetailView] content evaluated - safeAreaInsets.top: \(safeAreaInsets.top), navbar height: 44")

        ZStack {
            Color.black.ignoresSafeArea()

            mainContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: safeAreaInsets.top + 44)
                }
        }
    }

    var body: some View {
        let _ = print("📐 [ChannelDetailView] body evaluated - channelId: \(channelId)")

        ZStack {
            content
                .navigationBarHidden(true)

            // Custom navigation bar
            VStack {
                customNavigationBar
                    .onAppear {
                        print("📐 [ChannelDetailView] customNavigationBar appeared")
                    }
                Spacer()
            }
        }
        .edgesIgnoringSafeArea(.all)
        .fullScreenCover(isPresented: $showingUserProfile) {
            if let channel = viewModel.channel {
                UserProfileView(userId: channel.userId)
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(isPresented: $showingCreatePost) {
            if let channel = viewModel.channel {
                CreatePostViewForChannel(
                    channel: channel,
                    latestPostArtworkUrl: viewModel.posts.first?.artworkUrl
                )
                .environmentObject(authManager)
                .onAppear {
                    print("✅ [ChannelDetailView] fullScreenCover triggered with channel: \(channel.name)")
                }
            } else {
                EmptyView()
                    .onAppear {
                        print("❌ [ChannelDetailView] fullScreenCover triggered but channel is nil")
                    }
            }
        }
        .confirmationDialog(isOwnChannel ? "チャンネル設定" : "チャンネルオプション", isPresented: $showingChannelMenu, titleVisibility: .hidden) {
            if isOwnChannel {
                Button("チャンネルを削除", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } else {
                // Show follow/unfollow button based on current state
                if let channel = viewModel.channel {
                    if channel.isFollowing == true {
                        Button("フォロー解除") {
                            Task {
                                await unfollowChannel()
                            }
                        }
                    } else {
                        Button("フォロー") {
                            Task {
                                await followChannel()
                            }
                        }
                    }
                }

                Button("チャンネルを報告") {
                    // TODO: チャンネル報告機能実装
                }
                Button("ユーザーをブロック") {
                    Task {
                        await blockChannelOwner()
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("チャンネルを削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    await deleteChannel()
                }
            }
        } message: {
            Text("このチャンネルを削除してもよろしいですか？チャンネル内のすべての投稿も削除されます。この操作は取り消せません。")
        }
        .alert("ログインが必要です", isPresented: $showingLoginPrompt) {
            Button("はい") {
                showingLoginSheet = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この機能を使用するにはログインが必要です")
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            if #available(iOS 16.4, *) {
                LoginView()
                    .presentationBackground(Color.black)
                    .presentationCornerRadius(20)
            } else {
                LoginView()
            }
        }
        .alert("ログインが必要です", isPresented: $showingLoginAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("ログイン") {
                showingLoginSheet = true
            }
        } message: {
            Text("この機能を利用するにはログインが必要です")
        }
        .task {
            await viewModel.loadChannel(channelId: channelId)
        }
        .onChange(of: showingCreatePost) { newValue in
            print("🔄 [ChannelDetailView] showingCreatePost changed to: \(newValue)")
        }
    }

    private func deleteChannel() async {
        guard let channel = viewModel.channel, let channelId = channel.id else { return }

        do {
            try await FirestoreChannelManager.shared.deleteChannel(channelId: channelId)
            // チャンネル削除通知を発行
            NotificationCenter.default.post(
                name: Foundation.Notification.Name("ChannelDeleted"),
                object: nil,
                userInfo: ["channelId": channelId]
            )
            dismiss()
        } catch {
            print("❌ Failed to delete channel: \(error)")
        }
    }

    private func followChannel() async {
        guard authManager.isAuthenticated else {
            showingLoginPrompt = true
            return
        }

        guard let channel = viewModel.channel, let channelId = channel.id else { return }

        do {
            try await FirestoreChannelManager.shared.followChannel(channelId: channelId)
            // Update the channel's follow status
            viewModel.channel?.isFollowing = true
            print("✅ Followed channel: \(channelId)")
        } catch {
            print("❌ Failed to follow channel: \(error)")
        }
    }

    private func unfollowChannel() async {
        guard authManager.isAuthenticated else {
            showingLoginPrompt = true
            return
        }

        guard let channel = viewModel.channel, let channelId = channel.id else { return }

        do {
            try await FirestoreChannelManager.shared.unfollowChannel(channelId: channelId)
            // Update the channel's follow status
            viewModel.channel?.isFollowing = false
            print("✅ Unfollowed channel: \(channelId)")
        } catch {
            print("❌ Failed to unfollow channel: \(error)")
        }
    }

    private func blockChannelOwner() async {
        guard let channel = viewModel.channel else { return }
        guard authManager.isAuthenticated else { return }

        do {
            try await FirestoreBlockManager.shared.blockUser(userId: channel.userId)
            // ブロック通知を発行
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.userBlocked,
                object: nil,
                userInfo: ["blockedUserId": channel.userId]
            )
            dismiss()
        } catch {
            print("❌ Failed to block user: \(error)")
        }
    }
}

@MainActor
class ChannelDetailViewModel: ObservableObject {
    @Published var channel: Channel?
    @Published var channelOwner: User?  // Channel owner user info
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingPosts = false

    private var currentChannelId: String?

    init() {
        // チャンネルフォロー通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name("ChannelFollowed"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let channelId = notification.userInfo?["channelId"] as? String,
               channelId == self?.currentChannelId {
                Task { @MainActor in
                    await self?.loadChannel(channelId: channelId)
                }
            }
        }
    }

    func loadChannel(channelId: String) async {
        currentChannelId = channelId
        isLoading = true

        do {
            channel = try await FirestoreChannelManager.shared.getChannel(channelId: channelId)

            // Load channel owner info dynamically
            if let channel = channel {
                channelOwner = try? await FirestoreUserManager.shared.getUser(userId: channel.userId)
                print("✅ [ChannelDetailViewModel] Loaded channel: \(channel.name), owner: \(channelOwner?.username ?? "nil")")
            }
            await loadPosts(channelId: channelId)
        } catch {
            print("❌ Failed to load channel: \(error)")
        }

        isLoading = false
    }

    func loadPosts(channelId: String) async {
        isLoadingPosts = true

        do {
            // Get all posts for this channel
            let allPosts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId)
            posts = allPosts

            // Initialize like and comment states
            for post in posts {
                if let postId = post.id {
                    LikeStateManager.shared.initialize(postId: postId, isLiked: post.isLiked ?? false, count: post.likeCount)
                    CommentStateManager.shared.initialize(postId: postId, count: post.commentCount)
                }
            }

            print("✅ Loaded \(posts.count) posts for channel")
        } catch {
            print("❌ Failed to load channel posts: \(error)")
        }

        isLoadingPosts = false
    }
}

// MARK: - Channel Post Card (Grid Style - Discovery Tab)

struct ChannelPostCardGrid: View {
    let post: Post
    let channelName: String
    @Binding var showingLoginPrompt: Bool
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var likeState = LikeStateManager.shared
    @StateObject private var commentState = CommentStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @State private var showingPostMenu = false
    @State private var showingComments = false
    @State private var showingUserProfile = false
    @State private var showingReportPost = false
    @State private var showingReportChannel = false
    @State private var likeAnimationScale: CGFloat = 1.0
    @State private var menuAnimationScale: CGFloat = 1.0
    @State private var postUser: User? = nil

    private var isPlaying: Bool {
        guard let postId = post.id else { return false }
        return playbackState.isPlaying(postId)
    }

    private var isLiked: Bool {
        guard let postId = post.id else { return false }
        return likeState.isLiked(postId)
    }

    private var likeCount: Int {
        guard let postId = post.id else { return 0 }
        return likeState.getLikeCount(postId)
    }

    private var commentCount: Int {
        post.commentCount ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background image - full width
                ArtworkImageView(
                    artworkUrl: post.artworkUrl,
                    placeholder: "music.note",
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()

                // Loading indicator (centered)
                if musicKit.isLoadingPreview && isPlaying {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }

            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                // Top: Menu button only
                HStack {
                    Spacer()

                    Button(action: {
                        if !authManager.isAuthenticated {
                            showingLoginPrompt = true
                            return
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            menuAnimationScale = 0.8
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                menuAnimationScale = 1.0
                            }
                        }
                        showingPostMenu = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(20)
                            .rotationEffect(.degrees(90))
                    }
                    .scaleEffect(menuAnimationScale)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Spacer()

                // Bottom: Track info (left) and likes/comments (right)
                HStack(alignment: .bottom, spacing: 12) {
                    // Left: Track info
                    VStack(alignment: .leading, spacing: 4) {
                        // Track name with waveform animation
                        HStack(spacing: 6) {
                            Text(post.trackName ?? "")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if isPlaying {
                                MiniWaveformView()
                                    .frame(width: 30, height: 20)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)

                        // Artist name
                        Text(post.artistName ?? "")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)

                        // User info
                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            showingUserProfile = true
                        }) {
                            HStack(spacing: 6) {
                                if let user = postUser {
                                    AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image("recoreco")
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())

                                    Text(user.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                } else {
                                    Image("recoreco")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 20, height: 20)
                                        .clipShape(Circle())

                                    Text("Loading...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }

                                Text("・")
                                    .foregroundColor(.white.opacity(0.5))

                                Text(formatPostDate(post.createdAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                        }

                        // Comment
                        if let comment = post.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)
                        }

                        // Channel name
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                            Text(channelName)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                    }

                    Spacer()

                    // Right: Likes and comments (vertical)
                    VStack(alignment: .center, spacing: 10) {
                        // Like button
                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                likeAnimationScale = 1.3
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    likeAnimationScale = 1.0
                                }
                            }
                            Task {
                                await toggleLike()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 18))
                                    .foregroundColor(isLiked ? .red : .white.opacity(0.9))
                                    .scaleEffect(likeAnimationScale)
                                Text("\(likeCount)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                        }

                        // Comment button
                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            showingComments = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.9))
                                Text("\(commentCount)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            }
            .overlay(
                Rectangle()
                    .strokeBorder(
                        Color.white.opacity(0.7),
                        lineWidth: isPlaying ? 3 : 0
                    )
            )
            .onTapGesture {
                Task {
                    await togglePlayback()
                }
            }
        }
        .sheet(isPresented: $showingComments) {
            if #available(iOS 16.4, *) {
                NavigationStack {
                    CommentsView(post: post)
                }
                .presentationBackground(Color.black)
                .presentationCornerRadius(20)
            } else {
                NavigationStack {
                    CommentsView(post: post)
                }
            }
        }
        .sheet(isPresented: $showingUserProfile) {
            UserProfileView(userId: post.userId)
        }
        .confirmationDialog("投稿オプション", isPresented: $showingPostMenu, titleVisibility: .hidden) {
            if let appleMusicUrl = post.appleMusicUrl, let url = URL(string: appleMusicUrl) {
                Button("Apple Musicで開く") {
                    UIApplication.shared.open(url)
                }
            }

            if authManager.currentUser?.id == post.userId {
                Button("削除", role: .destructive) {
                    Task {
                        await deletePost()
                    }
                }
            } else {
                Button("投稿を報告") {
                    showingReportPost = true
                }
                Button("チャンネルを報告") {
                    showingReportChannel = true
                }
                Button("ユーザーをブロック") {
                    Task {
                        await blockUser()
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showingReportPost) {
            ReportPostView(post: post)
        }
        .sheet(isPresented: $showingReportChannel) {
            if let channelId = post.channelId {
                ReportChannelView(channelId: channelId, channelName: channelName)
            }
        }
        .task(id: post.id) {
            if postUser == nil {
                postUser = try? await FirestoreUserManager.shared.getUser(userId: post.userId)
            }
        }
        .onAppear {
            if let postId = post.id {
                likeState.updateFromServer(
                    postId: postId,
                    isLiked: post.isLiked ?? false,
                    count: post.likeCount ?? 0
                )
            }
        }
    }

    private func togglePlayback() async {
        guard let postId = post.id else { return }

        if playbackState.isPlaying(postId) {
            musicKit.stopPreview()
            playbackState.stopPlayback()
        } else {
            if let previewUrl = post.previewUrl {
                do {
                    try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                    playbackState.startPlayback(for: postId, userId: post.userId, post: post, user: nil)
                } catch {
                    print("❌ Failed to play preview: \(error)")
                }
            }
        }
    }

    private func toggleLike() async {
        if !authManager.isAuthenticated {
            showingLoginPrompt = true
            return
        }

        guard let postId = post.id else { return }

        let wasLiked = isLiked
        likeState.toggleLike(postId: postId)

        do {
            if wasLiked {
                try await FirestoreLikeManager.shared.unlikePost(postId: postId)
            } else {
                try await FirestoreLikeManager.shared.likePost(postId: postId)
            }
        } catch {
            likeState.toggleLike(postId: postId)
            print("❌ Failed to toggle like: \(error)")
        }
    }

    private func blockUser() async {
        guard authManager.isAuthenticated else {
            showingLoginPrompt = true
            return
        }

        do {
            try await FirestoreBlockManager.shared.blockUser(userId: post.userId)
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.userBlocked,
                object: nil,
                userInfo: ["blockedUserId": post.userId]
            )
        } catch {
            print("❌ Failed to block user: \(error)")
        }
    }

    private func deletePost() async {
        guard let postId = post.id else { return }

        do {
            try await FirestorePostManager.shared.deletePost(postId: postId)
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.postDeleted,
                object: nil,
                userInfo: ["postId": postId]
            )
            print("✅ Post deleted successfully")
        } catch {
            print("❌ Failed to delete post: \(error)")
        }
    }

    private func formatPostDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Channel Posts ViewModel
@MainActor
class ChannelPostsViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false

    func loadChannelPosts(channelId: String, latestPostId: String, forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            var allPosts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId, limit: 10, forceRefresh: forceRefresh)

            // 最新投稿を先頭に移動
            if let latestIndex = allPosts.firstIndex(where: { $0.id == latestPostId }) {
                let latestPost = allPosts.remove(at: latestIndex)
                allPosts.insert(latestPost, at: 0)
            }

            posts = allPosts
            print("✅ Loaded \(posts.count) posts for channel")
        } catch {
            print("❌ Failed to load channel posts: \(error)")
        }
    }
}

// MARK: - Wave Animation View
struct WaveAnimationView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple.opacity(0.8), Color.pink.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: animate ? 20 : 10)
                    .animation(
                        Animation
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Channel Post Card (List Style)

struct ChannelPostCard: View {
    let post: Post
    @Binding var showingLoginPrompt: Bool
    let channelName: String
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var likeState = LikeStateManager.shared
    @StateObject private var commentState = CommentStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @EnvironmentObject var authManager: AuthManager
    @State private var showingComments = false
    @State private var showingPostMenu = false
    @State private var showingUserProfile = false
    @State private var showingReportPost = false
    @State private var showingReportChannel = false
    @State private var likeAnimationScale: CGFloat = 1.0
    @State private var menuAnimationScale: CGFloat = 1.0
    @State private var postUser: User? = nil

    private var isPlaying: Bool {
        guard let postId = post.id else { return false }
        return playbackState.isPlaying(postId)
    }

    private var isLiked: Bool {
        guard let postId = post.id else { return false }
        return likeState.isLiked(postId)
    }

    private var likeCount: Int {
        guard let postId = post.id else { return 0 }
        return likeState.getLikeCount(postId)
    }

    private var commentCount: Int {
        post.commentCount ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = screenWidth // Square aspect ratio

            ZStack {
                // Background image
                ArtworkImageView(
                    artworkUrl: post.artworkUrl,
                    placeholder: "music.note",
                    width: screenWidth,
                    height: screenHeight
                )
                .frame(width: screenWidth, height: screenHeight)
                .clipped()

                // Loading indicator (centered)
                if musicKit.isLoadingPreview && isPlaying {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }

                // Content overlay
                VStack(alignment: .leading, spacing: 0) {
                    // Top: Menu button only
                    HStack {
                        Spacer()

                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                menuAnimationScale = 0.8
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    menuAnimationScale = 1.0
                                }
                            }
                            showingPostMenu = true
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(20)
                                .rotationEffect(.degrees(90))
                        }
                        .scaleEffect(menuAnimationScale)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    Spacer()

                    // Bottom: Track info (left) and likes/comments (right)
                    HStack(alignment: .bottom, spacing: 12) {
                        // Left: Track info
                        VStack(alignment: .leading, spacing: 4) {
                            // Track name with waveform animation
                            HStack(spacing: 6) {
                                Text(post.trackName ?? "")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                if isPlaying {
                                    MiniWaveformView()
                                        .frame(width: 30, height: 20)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)

                            // Artist name
                            Text(post.artistName ?? "")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)

                            // User info
                            Button(action: {
                                if !authManager.isAuthenticated {
                                    showingLoginPrompt = true
                                    return
                                }
                                showingUserProfile = true
                            }) {
                                HStack(spacing: 6) {
                                    if let user = postUser {
                                        AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image("recoreco")
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        }
                                        .frame(width: 20, height: 20)
                                        .clipShape(Circle())

                                        Text(user.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                    } else {
                                        Image("recoreco")
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 20, height: 20)
                                            .clipShape(Circle())

                                        Text("Loading...")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                    }

                                    Text("・")
                                        .foregroundColor(.white.opacity(0.5))

                                    Text(formatPostDate(post.createdAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)
                            }

                            // Comment
                            if let comment = post.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(6)
                            }

                            // Channel name
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.6))
                                Text(channelName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                        }

                        Spacer()

                        // Right: Likes and comments (vertical)
                        VStack(alignment: .center, spacing: 10) {
                            // Like button
                            Button(action: {
                                if !authManager.isAuthenticated {
                                    showingLoginPrompt = true
                                    return
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                    likeAnimationScale = 1.3
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                        likeAnimationScale = 1.0
                                    }
                                }
                                Task {
                                    await toggleLike()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                        .font(.system(size: 18))
                                        .foregroundColor(isLiked ? .red : .white.opacity(0.9))
                                        .scaleEffect(likeAnimationScale)
                                    Text("\(likeCount)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                            }

                            // Comment button
                            Button(action: {
                                if !authManager.isAuthenticated {
                                    showingLoginPrompt = true
                                    return
                                }
                                showingComments = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text("\(commentCount)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        Color.white.opacity(0.7),
                        lineWidth: isPlaying ? 3 : 0
                    )
            )
            .onTapGesture {
                Task {
                    await togglePlayback()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .sheet(isPresented: $showingComments) {
            if #available(iOS 16.4, *) {
                NavigationStack {
                    CommentsView(post: post)
                }
                .presentationBackground(Color.black)
                .presentationCornerRadius(20)
            } else {
                NavigationStack {
                    CommentsView(post: post)
                }
            }
        }
        .sheet(isPresented: $showingUserProfile) {
            UserProfileView(userId: post.userId)
        }
        .confirmationDialog("投稿オプション", isPresented: $showingPostMenu, titleVisibility: .hidden) {
            if let appleMusicUrl = post.appleMusicUrl, let url = URL(string: appleMusicUrl) {
                Button("Apple Musicで開く") {
                    UIApplication.shared.open(url)
                }
            }

            if authManager.currentUser?.id == post.userId {
                Button("削除", role: .destructive) {
                    Task {
                        await deletePost()
                    }
                }
            } else {
                Button("投稿を報告") {
                    showingReportPost = true
                }
                Button("チャンネルを報告") {
                    showingReportChannel = true
                }
                Button("ユーザーをブロック") {
                    Task {
                        await blockUser()
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showingReportPost) {
            ReportPostView(post: post)
        }
        .sheet(isPresented: $showingReportChannel) {
            if let channelId = post.channelId {
                ReportChannelView(channelId: channelId, channelName: channelName)
            }
        }
        .task(id: post.id) {
            if postUser == nil {
                postUser = try? await FirestoreUserManager.shared.getUser(userId: post.userId)
            }
        }
        .onAppear {
            if let postId = post.id {
                likeState.updateFromServer(
                    postId: postId,
                    isLiked: post.isLiked ?? false,
                    count: post.likeCount ?? 0
                )
            }
        }
    }

    private func togglePlayback() async {
        guard let postId = post.id else { return }

        if playbackState.isPlaying(postId) {
            musicKit.stopPreview()
            playbackState.stopPlayback()
        } else {
            if let previewUrl = post.previewUrl {
                do {
                    try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                    playbackState.startPlayback(for: postId, userId: post.userId, post: post, user: nil)
                } catch {
                    print("❌ Failed to play preview: \(error)")
                }
            }
        }
    }

    private func toggleLike() async {
        guard authManager.isAuthenticated, let postId = post.id else {
            showingLoginPrompt = true
            return
        }

        let wasLiked = isLiked
        likeState.toggleLike(postId: postId)

        do {
            if wasLiked {
                try await FirestoreLikeManager.shared.unlikePost(postId: postId)
            } else {
                try await FirestoreLikeManager.shared.likePost(postId: postId)
            }
        } catch {
            // Revert on error
            likeState.toggleLike(postId: postId)
            print("❌ Failed to toggle like: \(error)")
        }
    }

    private func deletePost() async {
        guard let postId = post.id else { return }

        do {
            try await FirestorePostManager.shared.deletePost(postId: postId)
            // 投稿削除通知を発行
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.postDeleted,
                object: nil,
                userInfo: ["postId": postId]
            )
        } catch {
            print("❌ Failed to delete post: \(error)")
        }
    }

    private func blockUser() async {
        guard authManager.isAuthenticated else {
            showingLoginPrompt = true
            return
        }

        do {
            try await FirestoreBlockManager.shared.blockUser(userId: post.userId)
            // ブロック通知を発行
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.userBlocked,
                object: nil,
                userInfo: ["blockedUserId": post.userId]
            )
        } catch {
            print("❌ Failed to block user: \(error)")
        }
    }

    private func formatPostDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Create Post View for Channel

struct CreatePostViewForChannel: View {
    let channel: Channel
    let latestPostArtworkUrl: String?
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = CreatePostViewModel()
    @EnvironmentObject var authManager: AuthManager
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isCommentFocused: Bool
    @State private var channelOwner: User? = nil

    // MARK: - Computed Properties for Performance

    @ViewBuilder
    private var mainContentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    channelInfoSection
                    musicSearchContentSection
                    commentSection

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding(.vertical)
                .padding(.bottom, viewModel.selectedSong != nil ? 100 : 0)
            }

            if viewModel.selectedSong != nil {
                createPostButtonView
            }
        }
    }

    @ViewBuilder
    private var createPostButtonView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.2))

            Button(action: {
                Task {
                    await createPost()
                }
            }) {
                Text("投稿する")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.selectedSong != nil && viewModel.comment.count <= 50 ? Color.blue : Color.gray)
                    .cornerRadius(0)
            }
            .disabled(viewModel.selectedSong == nil || viewModel.comment.count > 50 || viewModel.isPosting)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var musicSearchContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("曲を検索")
                .font(.headline)
                .foregroundColor(.white)

            searchBarView
            searchResultsView
            selectedSongView
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var searchBarView: some View {
        HStack {
            TextField("曲名・アーティスト名で検索", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit {
                    isSearchFocused = false
                    Task {
                        await viewModel.performSearch()
                    }
                }

            Button(action: {
                isSearchFocused = false
                Task {
                    await viewModel.performSearch()
                }
            }) {
                Text("検索")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(viewModel.searchQuery.isEmpty || viewModel.isSearching)
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if viewModel.isSearching {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding()
        } else if !viewModel.searchResults.isEmpty {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.searchResults) { song in
                    searchResultRow(song: song)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(song: Song) -> some View {
        Button(action: {
            isSearchFocused = false
            isCommentFocused = false
            Task {
                await viewModel.selectSong(song)
            }
        }) {
            HStack(spacing: 12) {
                if let artwork = song.artwork {
                    ArtworkImage(artwork, width: 50)
                        .cornerRadius(4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var selectedSongView: some View {
        if let song = viewModel.selectedSong {
            VStack(alignment: .leading, spacing: 12) {
                Text("選択中の曲")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                HStack(spacing: 12) {
                    if let artwork = song.artwork {
                        ArtworkImage(artwork, width: 80)
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(song.artistName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                previewButtonView
            }
        }
    }

    @ViewBuilder
    private var previewButtonView: some View {
        Button(action: {
            if viewModel.isPlaying {
                viewModel.stopPreview()
            } else {
                Task {
                    await viewModel.playPreview()
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                Text(viewModel.isPlaying ? "停止" : "30秒プレビュー再生")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: viewModel.isPlaying ?
                        [Color.red, Color.orange] :
                        [Color.green, Color.blue]
                    ),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
        }
        .disabled(viewModel.isFetchingPreview)
        .opacity(viewModel.isFetchingPreview ? 0.5 : 1.0)
    }

    @ViewBuilder
    private var commentSection: some View {
        if viewModel.selectedSong != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("紹介文（50文字以内）")
                    .font(.headline)
                    .foregroundColor(.white)

                ZStack(alignment: .topLeading) {
                    if viewModel.comment.isEmpty {
                        Text("この曲の魅力を教えてください（任意）")
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                    }

                    TextEditor(text: $viewModel.comment)
                        .frame(minHeight: 80)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .foregroundColor(.white)
                        .focused($isCommentFocused)
                }
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)

                Text("\(viewModel.comment.count)/50")
                    .font(.caption)
                    .foregroundColor(viewModel.comment.count > 50 ? .red : .white.opacity(0.5))
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var channelInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("投稿先チャンネル")
                .onAppear {
                    print("🎨 [CreatePostViewForChannel] Channel info section appeared")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 12) {
                // Channel creator profile image
                if let profileImageUrl = channelOwner?.profileImageUrl,
                   let url = URL(string: profileImageUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        } else {
                            Image("recoreco")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        }
                    }
                } else {
                    Image("recoreco")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                        Text(channel.name)
                            .font(.headline)
                            .foregroundColor(.white)
                    }

                    Text("by @\(channelOwner?.username ?? "unknown")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Latest post artwork
                if let artworkUrl = latestPostArtworkUrl,
                   let url = URL(string: artworkUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                mainContentView
            }
            .navigationTitle("投稿を作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarItems(
                leading: Button("キャンセル") {
                    dismiss()
                }
                .foregroundColor(.white),
                trailing: Button("完了") {
                    isCommentFocused = false
                    isSearchFocused = false
                }
                .foregroundColor(.white)
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        isCommentFocused = false
                        isSearchFocused = false
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onChange(of: viewModel.postCreated) { created in
            if created {
                dismiss()
            }
        }
        .task {
            channelOwner = try? await FirestoreUserManager.shared.getUser(userId: channel.userId)
            await viewModel.warmupSearch()
        }
    }

    private func createPost() async {
        viewModel.selectedChannel = channel
        await viewModel.createPost()
    }
}
