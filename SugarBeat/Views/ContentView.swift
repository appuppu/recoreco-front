import SwiftUI
import MusicKit

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @StateObject private var versionManager = AppVersionManager.shared
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
                        LoginRequiredView(showingLoginSheet: $showingLoginSheet, message: "投稿するには\nログインしてください")
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
                        LoginRequiredView(showingLoginSheet: $showingLoginSheet, message: "通知を見るには\nログインしてください")
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
                        LoginRequiredView(showingLoginSheet: $showingLoginSheet, message: "プロフィールを表示するには\nログインしてください")
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
        .overlay {
            if versionManager.isUpdateRequired {
                ForceUpdateView(appStoreUrl: versionManager.appStoreUrl)
            }
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
            // 起動時にアプリのバージョンをチェック（強制アップデート判定）
            await versionManager.checkForRequiredUpdate()

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
    let message: String

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

                Text(message)
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
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(width: 40, height: 40)
                                                    .overlay(
                                                        Image(systemName: "person.fill")
                                                            .font(.system(size: 20))
                                                            .foregroundColor(.white.opacity(0.5))
                                                    )
                                            }
                                        }
                                    } else {
                                        Circle()
                                            .fill(Color.white.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.white.opacity(0.5))
                                            )
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
