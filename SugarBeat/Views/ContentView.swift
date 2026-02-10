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

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var searchResults: [Channel] = []
    @State private var isSearchingDB = false
    @State private var selectedChannelType: ChannelType = .shared
    @State private var showingCompose42 = false
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !isSearching {
                        channelTypeSwitcher
                    }

                    if isSearching {
                        searchBar
                    }

                    contentArea
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
            .navigationTitle("すべてのチャンネル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isSearching = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .fullScreenCover(isPresented: $showingCompose42) {
                Compose42View()
                    .environmentObject(authManager)
            }
        }
        .task {
            await viewModel.loadChannels(channelType: .shared)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var channelTypeSwitcher: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation {
                    selectedChannelType = .shared
                    viewModel.filterChannels(by: .shared)
                }
            }) {
                Text("公開チャンネル")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedChannelType == .shared ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedChannelType == .shared ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                    .cornerRadius(8)
            }

            Button(action: {
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
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))

                TextField("チャンネル名を検索", text: $searchQuery)
                    .foregroundColor(.white)
                    .autocapitalization(.none)

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(10)

            Button(action: {
                Task {
                    await performSearch()
                }
            }) {
                Text("検索")
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

            Button(action: {
                isSearching = false
                searchQuery = ""
                searchResults = []
            }) {
                Text("キャンセル")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    @ViewBuilder
    private var contentArea: some View {
        if isSearching {
            // Search mode
            if isSearchingDB {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
                    Text("検索中...")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("チャンネルが見つかりません")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, channel in
                            ChannelDiscoveryCard(
                                channel: channel,
                                postId: channel.latestPostId ?? ""
                            )
                            .padding(.vertical, 4)

                            if index < searchResults.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.2))
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("チャンネル名を入力して\n検索ボタンを押してください")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Normal mode
            if viewModel.isLoading && viewModel.channels.isEmpty {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    print("🔄 [DiscoveryView] Initial loading ProgressView displayed")
                }
            } else if !viewModel.channels.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.channels.enumerated()), id: \.element.id) { index, channel in
                                ChannelDiscoveryCard(
                                    channel: channel,
                                    postId: channel.latestPostId ?? ""
                                )
                                .padding(.vertical, 4)

                                if index < viewModel.channels.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.2))
                                        .padding(.vertical, 4)
                                }

                                // パターン: ch0 → ad → ch1,2 → ad → ch3 → ad → ch4,5 → ad → ...
                                let shouldShowAd = (index == 0) || ((index - 1) % 3 == 2)
                                if shouldShowAd && AdConfig.shouldShowAds {
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
                        await viewModel.refreshChannels(channelType: selectedChannelType)
                    }
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func performSearch() async {
        isSearchingDB = true

        do {
            let results = try await FirestoreChannelManager.shared.searchChannels(query: searchQuery)
            searchResults = results
        } catch {
            print("❌ Failed to search channels: \(error)")
            searchResults = []
        }

        isSearchingDB = false
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
                                    channelId: channel.id ?? "",
                                    showingLoginPrompt: $showingLoginPrompt,
                                    showingChannelDetail: $showingChannelDetail,
                                    viewModel: viewModel
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
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    } else if phase.error != nil {
                        // Error loading image
                        profilePlaceholder
                    } else {
                        // Loading in progress
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                    }
                }
            } else {
                profilePlaceholder
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 50, height: 50)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.5))
            )
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
                        // Channel type icon
                        Image(systemName: channel.channelType == .shared ? "globe" : "person.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text(channel.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        // 公開タグ
                        if channel.channelType == .shared {
                            Text("公開")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
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
    private var currentChannelType: ChannelType = .shared

    init() {
        // Listen for post created notifications
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                print("📥 [DiscoveryViewModel] Received postCreated notification")
                // Reload channels to get updated latestPostId
                print("🔄 [DiscoveryViewModel] Refreshing channels for type: \(self.currentChannelType.rawValue)")
                await self.refreshChannels(channelType: self.currentChannelType)
            }
        }

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

    func loadChannels(channelType: ChannelType = .shared) async {
        isLoading = true
        currentChannelType = channelType
        defer { isLoading = false }

        do {
            // Fetch channels filtered by type directly from Firestore
            channels = try await FirestorePostManager.shared.getDiscoveryChannels(channelType: channelType, limit: 100)
            print("✅ [DiscoveryViewModel] Loaded \(channels.count) \(channelType.rawValue) channels")
        } catch {
            print("❌ Failed to load channels: \(error)")
        }
    }

    func refreshChannels(channelType: ChannelType) async {
        // Refresh without setting isLoading to avoid double animation
        print("🔄 [DiscoveryViewModel] refreshChannels called for type: \(channelType.rawValue)")
        currentChannelType = channelType
        do {
            // Fetch channels filtered by type directly from Firestore
            channels = try await FirestorePostManager.shared.getDiscoveryChannels(channelType: channelType, limit: 100)
            print("✅ [DiscoveryViewModel] Refreshed \(channels.count) \(channelType.rawValue) channels")
        } catch {
            print("❌ Failed to refresh channels: \(error)")
        }
    }

    func filterChannels(by channelType: ChannelType) {
        currentChannelType = channelType
        Task {
            await refreshChannels(channelType: channelType)
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
    @State private var showingLeaveConfirmation = false
    @State private var showingRenameDialog = false
    @State private var showingMemberManagement = false
    @State private var newChannelName = ""
    @State private var floatingButtonScale: CGFloat = 1.0

    private var isOwnChannel: Bool {
        guard let currentUserId = authManager.currentUser?.id else {
            print("⚠️ [ChannelDetailView] isOwnChannel: No current user")
            return false
        }
        let result = viewModel.channel?.userId == currentUserId
        print("🔍 [ChannelDetailView] isOwnChannel: \(result), currentUserId: \(currentUserId), channelUserId: \(viewModel.channel?.userId ?? "nil")")
        return result
    }

    private func shouldShowPostButton(for channel: Channel) -> Bool {
        // 公開チャンネルの場合：誰でも投稿可能
        if channel.channelType == .shared {
            return true
        }
        // 個人チャンネルの場合：オーナーのみ投稿可能
        return isOwnChannel
    }

    private var floatingPostButton: some View {
        Button(action: {
            if !authManager.isAuthenticated {
                showingLoginAlert = true
                return
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                floatingButtonScale = 0.85
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    floatingButtonScale = 1.0
                }
            }
            showingCreatePost = true
        }) {
            ZStack {
                // Background layer with border
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                            .frame(width: 60, height: 60)
                    )

                // Icon
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .scaleEffect(floatingButtonScale)
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
                        // Channel type icon
                        Image(systemName: channel.channelType == .shared ? "globe" : "person.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
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
                        if channel.channelType == .shared {
                            Text("\(channel.followerCount ?? 0)人が参加")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        } else {
                            Text("\(channel.followerCount ?? 0)人がフォロー")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("チャンネル詳細")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()

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
                                    buttonText: channel.channelType == .shared ? "チャンネルに参加する" : "チャンネルをフォローする"
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

            // Floating action button
            if let channel = viewModel.channel, shouldShowPostButton(for: channel) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        floatingPostButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 30)
                    }
                }
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
                Button("チャンネル名を変更") {
                    showingRenameDialog = true
                }

                // Show member/follower management for all channels
                if let channel = viewModel.channel {
                    let buttonText = channel.channelType == .shared ? "メンバー管理" : "フォロワーをみる"
                    Button(buttonText) {
                        showingMemberManagement = true
                    }
                }

                Button("チャンネルを削除", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } else {
                // Show member/follower list for all channels
                if let channel = viewModel.channel {
                    let buttonText = channel.channelType == .shared ? "参加者をみる" : "フォロワーをみる"
                    Button(buttonText) {
                        showingMemberManagement = true
                    }
                }

                // Show follow/unfollow or join/leave button based on channel type
                if let channel = viewModel.channel {
                    if channel.isFollowing == true {
                        if channel.channelType == .shared {
                            Button("退出する", role: .destructive) {
                                showingLeaveConfirmation = true
                            }
                        } else {
                            Button("フォロー解除") {
                                Task {
                                    await unfollowChannel()
                                }
                            }
                        }
                    } else {
                        let buttonText = channel.channelType == .shared ? "参加する" : "フォロー"
                        Button(buttonText) {
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
        .alert("チャンネルから退出", isPresented: $showingLeaveConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("退出", role: .destructive) {
                Task {
                    await leaveChannel()
                }
            }
        } message: {
            Text("このチャンネルから退出してもよろしいですか？あなたがこのチャンネルに投稿したすべての投稿（いいねとコメントを含む）が削除されます。この操作は取り消せません。")
        }
        .alert("チャンネル名を変更", isPresented: $showingRenameDialog) {
            TextField("新しいチャンネル名", text: $newChannelName)
            Button("キャンセル", role: .cancel) {
                newChannelName = ""
            }
            Button("変更") {
                Task {
                    await renameChannel()
                }
            }
        } message: {
            Text("新しいチャンネル名を入力してください（30文字以内）")
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
        .sheet(isPresented: $showingMemberManagement) {
            if let channel = viewModel.channel, let channelId = channel.id {
                ChannelMemberManagementView(channelId: channelId)
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

    private func leaveChannel() async {
        guard authManager.isAuthenticated else {
            showingLoginPrompt = true
            return
        }

        guard let channel = viewModel.channel, let channelId = channel.id else { return }

        do {
            try await FirestoreChannelManager.shared.leaveChannelAndDeletePosts(channelId: channelId)
            print("✅ Left channel and deleted posts: \(channelId)")
            dismiss()
        } catch {
            print("❌ Failed to leave channel: \(error)")
        }
    }

    private func renameChannel() async {
        guard let channel = viewModel.channel, let channelId = channel.id else { return }

        let trimmedName = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, trimmedName.count <= 30 else {
            newChannelName = ""
            return
        }

        do {
            try await FirestoreChannelManager.shared.updateChannelName(channelId: channelId, name: trimmedName)
            viewModel.channel?.name = trimmedName
            newChannelName = ""
            print("✅ Renamed channel: \(channelId) -> \(trimmedName)")

            // Notify other views to refresh
            NotificationCenter.default.post(
                name: Foundation.Notification.Name("ChannelUpdated"),
                object: nil,
                userInfo: ["channelId": channelId]
            )
        } catch {
            print("❌ Failed to rename channel: \(error)")
            newChannelName = ""
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

        // 投稿作成通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("📥 [ChannelDetailViewModel] Received postCreated notification")
                if let channelId = self?.currentChannelId {
                    print("📥 [ChannelDetailViewModel] Current channelId: \(channelId), reloading posts...")
                    await self?.loadPosts(channelId: channelId, forceRefresh: true)
                } else {
                    print("⚠️ [ChannelDetailViewModel] currentChannelId is nil, cannot reload posts")
                }
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
                    self?.posts.removeAll { $0.id == postId }
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

    func loadPosts(channelId: String, forceRefresh: Bool = false) async {
        isLoadingPosts = true

        do {
            // Get all posts for this channel
            let allPosts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId, forceRefresh: forceRefresh)
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
    let channelId: String
    @Binding var showingLoginPrompt: Bool
    @Binding var showingChannelDetail: Bool
    @ObservedObject var viewModel: ChannelPostsViewModel
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
                // Top: Channel button (left) and Menu button (right)
                HStack {
                    // チャンネルへボタン
                    Button(action: {
                        showingChannelDetail = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 12))
                            Text("チャンネルへ")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(15)
                    }

                    Spacer()

                    // メニューボタン
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
                                        Circle()
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.5))
                                            )
                                    }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())

                                    Text(user.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                } else {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.5))
                                        )

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

            // 即座にUIから削除
            await MainActor.run {
                viewModel.removePost(postId: postId)
            }

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

    init() {
        // 投稿削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let postId = notification.userInfo?["postId"] as? String {
                Task { @MainActor in
                    self?.removePost(postId: postId)
                }
            }
        }
    }

    func loadChannelPosts(channelId: String, latestPostId: String, forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allPosts = try await FirestorePostManager.shared.getChannelPosts(channelId: channelId, limit: 10, forceRefresh: forceRefresh)

            // Posts are already sorted by createdAt descending from Firestore
            posts = allPosts
            print("✅ Loaded \(posts.count) posts for channel (sorted by latest)")
        } catch {
            print("❌ Failed to load channel posts: \(error)")
        }
    }

    func removePost(postId: String) {
        posts.removeAll { $0.id == postId }
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
                    // Top: User info (left) and Menu button (right)
                    HStack(alignment: .top) {
                        // User info - moved to top left
                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            showingUserProfile = true
                        }) {
                            HStack(spacing: 8) {
                                if let user = postUser {
                                    AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.white.opacity(0.5))
                                            )
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)

                                        Text(formatPostDate(post.createdAt))
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                } else {
                                    Image("recoreco")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())

                                    Text("Loading...")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                        }

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
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white.opacity(0.5))
                        )
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

// MARK: - Channel Member Management View

struct ChannelMemberManagementView: View {
    let channelId: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = ChannelMemberViewModel()

    private var isOwner: Bool {
        authManager.currentUser?.id == viewModel.channelOwnerId
    }

    private var navigationTitle: String {
        guard let channel = viewModel.channel else { return "読み込み中..." }

        if channel.channelType == .shared {
            return isOwner ? "メンバー管理" : "参加者をみる"
        } else {
            return "フォロワーをみる"
        }
    }

    private var emptyMessage: String {
        guard let channel = viewModel.channel else { return "読み込み中..." }

        if channel.channelType == .shared {
            return "メンバーがいません"
        } else {
            return "フォロワーがいません"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if viewModel.members.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                        Text(emptyMessage)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.members) { member in
                                MemberRow(
                                    member: member,
                                    isOwner: member.id == viewModel.channelOwnerId,
                                    canKick: viewModel.channel?.channelType == .shared && isOwner && member.id != viewModel.channelOwnerId
                                ) {
                                    Task {
                                        await viewModel.kickMember(userId: member.id ?? "", channelId: channelId)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            await viewModel.loadMembers(channelId: channelId)
        }
    }
}

struct MemberRow: View {
    let member: User
    let isOwner: Bool
    let canKick: Bool
    let onKick: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            if let profileImageUrl = member.profileImageUrl, let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if isOwner {
                        Text("オーナー")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text("@\(member.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            if canKick {
                Button(action: onKick) {
                    Text("キック")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
class ChannelMemberViewModel: ObservableObject {
    @Published var members: [User] = []
    @Published var isLoading = false
    @Published var channelOwnerId: String?
    @Published var channel: Channel?

    func loadMembers(channelId: String) async {
        isLoading = true

        do {
            // Get channel to find owner and type
            let fetchedChannel = try await FirestoreChannelManager.shared.getChannel(channelId: channelId)
            channel = fetchedChannel
            channelOwnerId = fetchedChannel.userId

            // Get channel followers
            let followers = try await FirestoreChannelManager.shared.getChannelFollowers(channelId: channelId)

            // Load user info for each follower
            var users: [User] = []
            for followerId in followers {
                if let user = try? await FirestoreUserManager.shared.getUser(userId: followerId) {
                    users.append(user)
                }
            }

            // Add owner at the top if not already in list
            if let ownerId = channelOwnerId, !followers.contains(ownerId) {
                if let owner = try? await FirestoreUserManager.shared.getUser(userId: ownerId) {
                    users.insert(owner, at: 0)
                }
            } else if let ownerId = channelOwnerId, let ownerIndex = users.firstIndex(where: { $0.id == ownerId }) {
                // Move owner to the top if already in list
                let owner = users.remove(at: ownerIndex)
                users.insert(owner, at: 0)
            }

            members = users
        } catch {
            print("❌ Failed to load members: \(error)")
        }

        isLoading = false
    }

    func kickMember(userId: String, channelId: String) async {
        do {
            try await FirestoreChannelManager.shared.kickMember(channelId: channelId, userId: userId)
            members.removeAll { $0.id == userId }
        } catch {
            print("❌ Failed to kick member: \(error)")
        }
    }
}

// MARK: - Channel Search View

struct ChannelSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ChannelSearchViewModel()
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("チャンネル名を検索", text: $viewModel.searchQuery)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .submitLabel(.search)
                            .onSubmit {
                                Task {
                                    await viewModel.searchChannels()
                                }
                            }
                        
                        if !viewModel.searchQuery.isEmpty {
                            Button(action: {
                                viewModel.searchQuery = ""
                                viewModel.searchResults = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
                    
                    // Results
                    if viewModel.isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding()
                    } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.3))
                            Text("チャンネルが見つかりません")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding()
                    } else if !viewModel.searchResults.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.searchResults) { channel in
                                    if let channelId = channel.id {
                                        NavigationLink(destination: ChannelDetailView(channelId: channelId)) {
                                            ChannelSearchResultRow(channel: channel)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding()
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.3))
                            Text("チャンネル名を入力してください")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .navigationTitle("チャンネル検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onChange(of: viewModel.searchQuery) { newValue in
            if !newValue.isEmpty {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
                    if viewModel.searchQuery == newValue {
                        await viewModel.searchChannels()
                    }
                }
            }
        }
    }
}

struct ChannelSearchResultRow: View {
    let channel: Channel
    @StateObject private var ownerViewModel = ChannelOwnerViewModel()
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            if let profileImageUrl = ownerViewModel.owner?.profileImageUrl,
               let url = URL(string: profileImageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Channel type icon
                    Image(systemName: channel.channelType == .shared ? "globe" : "person.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Text(channel.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                if let owner = ownerViewModel.owner {
                    Text("@\(owner.username)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    if channel.channelType == .shared {
                        Text("\(channel.followerCount ?? 0)人が参加")
                            .font(.caption)
                    } else {
                        Text("\(channel.followerCount ?? 0)人がフォロー")
                            .font(.caption)
                    }
                }
                .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await ownerViewModel.loadOwner(userId: channel.userId)
        }
    }
}

@MainActor
class ChannelSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [Channel] = []
    @Published var isSearching = false
    
    func searchChannels() async {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            let channels = try await FirestoreChannelManager.shared.searchChannels(query: searchQuery)
            searchResults = channels
        } catch {
            print("❌ Failed to search channels: \(error)")
            searchResults = []
        }
        
        isSearching = false
    }
}

@MainActor
class ChannelOwnerViewModel: ObservableObject {
    @Published var owner: User?
    
    func loadOwner(userId: String) async {
        do {
            owner = try await FirestoreUserManager.shared.getUser(userId: userId)
        } catch {
            print("❌ Failed to load channel owner: \(error)")
        }
    }
}
