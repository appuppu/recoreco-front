import SwiftUI
import FirebaseAuth

/// プロフィールタブ - 自分の投稿一覧を表示（発見タブと同じデザイン）
struct MyProfileView: View {
    @Binding var pendingPlayPostId: String?
    @StateObject private var viewModel = MyProfileViewModel()
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false
    @State private var showingUserSearch = false
    @State private var showingScreenshotTip = false
    @State private var showingSettings = false
    @State private var showingShareScreen = false
    @State private var isArtworkOnlyMode = false
    @State private var viewMode: ViewMode = .posts

    enum ViewMode {
        case posts
        case channels
    }

    init(pendingPlayPostId: Binding<String?> = .constant(nil)) {
        self._pendingPlayPostId = pendingPlayPostId
    }

    @ViewBuilder
    private var mainContent: some View {
        if isArtworkOnlyMode {
            // アルバムアートのみのグリッド表示
            artworkOnlyGrid
        } else if !authManager.isAuthenticated {
            // 未ログイン状態
            VStack(spacing: 20) {
                Image(systemName: "person.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.4))
                Text("ログインして\n自分の投稿を見る")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("ログイン") {
                    showingLoginSheet = true
                }
                .foregroundColor(.purple)
                .font(.headline)
            }
        } else {
            VStack(spacing: 0) {
                // プロフィール情報ヘッダー
                if let currentUser = authManager.currentUser {
                    userInfoHeader(user: currentUser)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }

                // コンテンツ
                if viewMode == .posts {
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.red.opacity(0.7))
                            Text(errorMessage)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                            Button("再読み込み") {
                                Task {
                                    await viewModel.loadPosts()
                                }
                            }
                            .foregroundColor(.purple)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if viewModel.posts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.4))
                            Text("まだ投稿がありません")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                            Text("左下の+ボタンから\n音楽を投稿してみましょう")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        PostGridView(
                            posts: viewModel.posts,
                            showingLoginPrompt: $showingLoginPrompt,
                            showUserInfo: true,
                            isLoading: viewModel.isLoading,
                            onRefresh: {
                                await viewModel.loadPosts(forceRefresh: true)
                            }
                        )
                        .environmentObject(authManager)
                    }
                } else {
                    channelsListView
                }
            }
        }
    }

    @ViewBuilder
    private var artworkOnlyGrid: some View {
        GeometryReader { geometry in
            let columns = 3
            let spacing: CGFloat = 2
            let itemWidth = (geometry.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                    // 最初のセル: ユーザー情報
                    if let currentUser = authManager.currentUser {
                        ZStack {
                            Color.black

                            VStack(spacing: 8) {
                                // プロフィール画像
                                AsyncImage(url: URL(string: currentUser.profileImageUrl ?? "")) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Image("recoreco")
                                            .resizable()
                                            .scaledToFill()
                                    }
                                }
                                .frame(width: itemWidth * 0.5, height: itemWidth * 0.5)
                                .clipShape(Circle())

                                // ユーザー名
                                Text("@\(currentUser.username)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: itemWidth, height: itemWidth)
                    }

                    // 残りのセル: アルバムアート
                    ForEach(viewModel.posts) { post in
                        if let artworkUrl = post.artworkUrl, let url = URL(string: artworkUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: itemWidth, height: itemWidth)
                            .clipped()
                        }
                    }
                }
                .padding(.bottom, 100) // タブバーの高さ分の余白
            }
            .persistentSystemOverlays(.hidden) // ホームインジケーターを非表示
            .onTapGesture {
                // スクショモードを終了して共有画面を表示
                withAnimation {
                    isArtworkOnlyMode = false
                    screenshotMode.isScreenshotMode = false
                }
                showingShareScreen = true
            }
        }
    }


    var body: some View {
        let _ = Self._printChanges()

        return NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.black
                    .ignoresSafeArea()
                mainContent
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isArtworkOnlyMode ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbar {
                if !isArtworkOnlyMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            showingUserSearch = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            // プロフィールリンク共有ボタン
                            Button(action: {
                                shareProfileLink()
                            }) {
                                Image(systemName: "link")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }

                            // スクショボタン
                            Button(action: {
                                if isArtworkOnlyMode {
                                    // スクショモード解除
                                    withAnimation {
                                        isArtworkOnlyMode = false
                                        screenshotMode.isScreenshotMode = false
                                    }
                                } else {
                                    // スクショモード開始: モーダルを表示
                                    showingScreenshotTip = true
                                }
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
            .overlay {
                // Screenshot mode tip modal
                if showingScreenshotTip {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()

                    VStack(spacing: 24) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)

                        Text("スクショを撮って\nSNSに投稿しよう！")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)

                        // OKボタン
                        Button(action: {
                            showingScreenshotTip = false
                            // 音楽を停止してスクショモードに入る
                            PlaybackStateManager.shared.stopPlayback()
                            MusicKitManager.shared.stopPreview()
                            withAnimation {
                                isArtworkOnlyMode = true
                                screenshotMode.isScreenshotMode = true
                            }
                            print("📸 Screenshot mode enabled (OK button)")
                        }) {
                            Text("OK")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color(hex: "cc208e"), Color(hex: "6713d2")]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.black.opacity(0.95))
                    )
                    .padding(.horizontal, 40)
                }
            }
            .onAppear {
                print("📱 [MyProfileView] onAppear - viewMode: \(viewMode), isAuthenticated: \(authManager.isAuthenticated), posts.isEmpty: \(viewModel.posts.isEmpty)")
                if viewModel.posts.isEmpty && authManager.isAuthenticated {
                    print("📱 [MyProfileView] Loading posts from onAppear...")
                    Task {
                        await viewModel.loadPosts()
                    }
                }
            }
            .task {
                print("📱 [MyProfileView] .task executed - isAuthenticated: \(authManager.isAuthenticated), posts.isEmpty: \(viewModel.posts.isEmpty)")
                if viewModel.posts.isEmpty && authManager.isAuthenticated {
                    print("📱 [MyProfileView] Loading posts...")
                    await viewModel.loadPosts()
                }
            }
            .onChange(of: authManager.isAuthenticated) { isAuthenticated in
                if isAuthenticated && viewModel.posts.isEmpty {
                    Task {
                        await viewModel.loadPosts()
                    }
                }
            }
            .onChange(of: pendingPlayPostId) { postId in
                if let postId = postId {
                    playPendingPost(postId: postId)
                }
            }
            .onChange(of: viewModel.posts.count) { _ in
                // Posts loaded, check if we have a pending post to play
                if let postId = pendingPlayPostId {
                    playPendingPost(postId: postId)
                }
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
                NavigationStack {
                    LoginView()
                }
            }
            .sheet(isPresented: $showingUserSearch) {
                NavigationStack {
                    UserSearchView()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showingShareScreen) {
                ProfileShareView(authManager: authManager)
            }
        }
    }

    private func playPendingPost(postId: String) {
        guard let post = viewModel.posts.first(where: { $0.id == postId }),
              let postId = post.id else {
            // Post not found yet, wait for posts to load
            return
        }

        // Clear the pending post ID
        pendingPlayPostId = nil

        // Start playback
        Task {
            if let previewUrl = post.previewUrl {
                do {
                    try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                    playbackState.startPlayback(for: postId, userId: post.userId, post: post, user: nil)
                    print("🎵 Playing post from notification: \(postId)")
                } catch {
                    print("❌ Failed to play post: \(error)")
                }
            }
        }
    }

    // MARK: - User Info Header
    @ViewBuilder
    private func userInfoHeader(user: User) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // プロフィール画像
                AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image("recoreco")
                        .resizable()
                        .scaledToFill()
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // 設定ボタン
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // 切り替えボタン
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation {
                        viewMode = .posts
                    }
                }) {
                    Text("投稿")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewMode == .posts ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewMode == .posts ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(8)
                }

                Button(action: {
                    withAnimation {
                        viewMode = .channels
                    }
                    if viewModel.channels.isEmpty, let userId = authManager.currentUser?.id {
                        Task {
                            await viewModel.loadChannels(userId: userId)
                        }
                    }
                }) {
                    Text("チャンネル")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewMode == .channels ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewMode == .channels ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(8)
                }
            }
        }
    }

    @ViewBuilder
    private var channelsListView: some View {
        if viewModel.channels.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.4))
                Text("チャンネルがありません")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.channels) { channel in
                        if let channelId = channel.id {
                            NavigationLink(destination: ChannelDetailView(channelId: channelId)) {
                                ChannelRowView(channel: channel)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            ChannelRowView(channel: channel)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
    }

    private func shareProfileLink() {
        guard let currentUser = authManager.currentUser,
              let url = DeepLinkManager.generateProfileURL(username: currentUser.username) else {
            print("❌ [MyProfileView] Cannot generate profile URL")
            return
        }

        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // iPadのためのpopover設定
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {

            if let popover = activityController.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootViewController.present(activityController, animated: true)
            print("✅ [MyProfileView] Sharing profile URL: \(url.absoluteString)")
        }
    }
}

// MARK: - ViewModel
@MainActor
class MyProfileViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var lastFetchTime: Date?
    private let cacheValidDuration: TimeInterval = 30 // 30秒キャッシュ

    init() {
        // 投稿完了通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadPosts(forceRefresh: true)
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

    func loadPosts(forceRefresh: Bool = false) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            errorMessage = "ユーザー情報を取得できません"
            isLoading = false
            return
        }

        let startTime = Date()
        let minimumLoadingTime: TimeInterval = 1.5

        // 初回ロードまたはプルリフレッシュの場合はローディング表示
        if forceRefresh || posts.isEmpty {
            isLoading = true
        }

        // キャッシュが有効な場合はスキップ（30秒以内）
        if let lastFetch = lastFetchTime {
            let elapsed = Date().timeIntervalSince(lastFetch)
            if elapsed < cacheValidDuration && !posts.isEmpty {
                print("📦 My Profile: Using cache (elapsed: \(Int(elapsed))s)")
                // キャッシュ使用時もローディングアニメーションを表示
                if forceRefresh {
                    try? await Task.sleep(nanoseconds: UInt64(minimumLoadingTime * 1_000_000_000))
                    isLoading = false
                }
                return
            }
        }

        errorMessage = nil

        do {
            // 自分の投稿を取得（新しい順）
            let (fetchedPosts, _) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 50)
            posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
            lastFetchTime = Date()
            print("📥 My Profile: Loaded \(posts.count) posts")
        } catch let error as NSError {
            // キャンセルエラー(-999)は無視
            if error.code == NSURLErrorCancelled {
                print("⚠️ My Profile: Request cancelled")
            } else {
                errorMessage = "読み込みに失敗しました"
                print("❌ My Profile: Failed to load posts: \(error)")
            }
        }

        // プルリフレッシュの場合は最低1.5秒間ローディングを表示
        if forceRefresh {
            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime < minimumLoadingTime {
                try? await Task.sleep(nanoseconds: UInt64((minimumLoadingTime - elapsedTime) * 1_000_000_000))
            }
        }

        isLoading = false
    }

    func loadChannels(userId: String) async {
        do {
            channels = try await FirestoreChannelManager.shared.getUserChannels(userId: userId)
            print("✅ Loaded \(channels.count) channels for user: \(userId)")
        } catch {
            errorMessage = "チャンネルの取得に失敗しました"
            print("❌ Failed to load channels: \(error)")
        }
    }
}
