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

    // Screenshot grid selection
    @State private var showingGridSelection = false
    @State private var showingPostSelection = false
    @State private var selectedGridType: GridType?
    @State private var selectedPosts: [Post] = []

    enum ViewMode {
        case posts
        case channels
    }

    struct GridType: Identifiable {
        let id = UUID()
        let count: Int
        let rows: Int
        let columns: Int

        var displayText: String {
            "\(count)(\(columns)×\(rows))"
        }

        static let availableTypes: [GridType] = [
            GridType(count: 4, rows: 2, columns: 2),
            GridType(count: 6, rows: 3, columns: 2),
            GridType(count: 9, rows: 3, columns: 3),
            GridType(count: 12, rows: 4, columns: 3),
            GridType(count: 15, rows: 5, columns: 3),
            GridType(count: 16, rows: 4, columns: 4),
            GridType(count: 20, rows: 5, columns: 4),
            GridType(count: 25, rows: 5, columns: 5),
            GridType(count: 36, rows: 6, columns: 6),
            GridType(count: 42, rows: 7, columns: 6)
        ]
    }

    init(pendingPlayPostId: Binding<String?> = .constant(nil)) {
        self._pendingPlayPostId = pendingPlayPostId
    }

    @ViewBuilder
    private var mainContent: some View {
        if !authManager.isAuthenticated {
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
        if let gridType = selectedGridType, !selectedPosts.isEmpty {
            DynamicArtworkGrid(posts: selectedPosts, columns: gridType.columns, rows: gridType.rows)
                .contentShape(Rectangle())
                .onTapGesture {
                    // スクショモードを終了して共有画面を表示
                    withAnimation {
                        isArtworkOnlyMode = false
                        screenshotMode.isScreenshotMode = false
                    }
                    showingShareScreen = true
                }
        } else {
            // Fallback: 全投稿を3x3で表示
            DynamicArtworkGrid(posts: viewModel.posts, columns: 3, rows: 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isArtworkOnlyMode = false
                        screenshotMode.isScreenshotMode = false
                    }
                    showingShareScreen = true
                }
        }
    }


    var body: some View {
        NavigationStack {
            Group {
                if isArtworkOnlyMode {
                    // スクショモード: ZStackを使わず全画面表示
                    artworkOnlyGrid
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        Color.black
                            .ignoresSafeArea()
                        mainContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isArtworkOnlyMode ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbar(isArtworkOnlyMode ? .hidden : .visible, for: .tabBar)
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

                        // グリッド選択ボタン
                        Button(action: {
                            showingScreenshotTip = false
                            // 音楽を停止
                            PlaybackStateManager.shared.stopPlayback()
                            MusicKitManager.shared.stopPreview()
                            // 前回の選択状態をリセット
                            selectedPosts = []
                            selectedGridType = nil
                            // グリッド選択画面を表示
                            showingGridSelection = true
                        }) {
                            Text("グリッド選択へ")
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
            .onChange(of: isArtworkOnlyMode) { newValue in
                // スクショモードを終了した時に選択状態をリセット
                if !newValue {
                    selectedPosts = []
                    selectedGridType = nil
                }
            }
            .fullScreenCover(isPresented: $showingGridSelection) {
                GridTypeSelectionView(
                    totalPosts: viewModel.posts.count,
                    selectedGridType: $selectedGridType,
                    selectedPosts: $selectedPosts,
                    showingGridSelection: $showingGridSelection,
                    showingPostSelection: $showingPostSelection
                )
            }
            .fullScreenCover(isPresented: $showingPostSelection) {
                if let gridType = selectedGridType {
                    PostSelectionView(
                        posts: viewModel.posts,
                        gridType: gridType,
                        selectedPosts: $selectedPosts,
                        selectedGridType: $selectedGridType,
                        showingPostSelection: $showingPostSelection,
                        isArtworkOnlyMode: $isArtworkOnlyMode,
                        screenshotMode: $screenshotMode.isScreenshotMode
                    )
                }
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
                            ZStack(alignment: .trailing) {
                                NavigationLink(destination: ChannelDetailView(channelId: channelId)) {
                                    ChannelRowView(channel: channel, isEditable: false)
                                }
                                .buttonStyle(PlainButtonStyle())

                                // 編集ボタンを上に重ねる
                                Button(action: {
                                    viewModel.editingChannel = channel
                                    viewModel.editingChannelName = channel.name
                                    viewModel.showEditChannelSheet = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.trailing, 16)
                                }
                            }
                        } else {
                            ChannelRowView(channel: channel)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .sheet(isPresented: $viewModel.showEditChannelSheet) {
                EditChannelNameSheet(
                    channelName: $viewModel.editingChannelName,
                    onSave: {
                        Task {
                            await viewModel.updateChannelName()
                        }
                    }
                )
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

// MARK: - Grid Type Selection View
struct GridTypeSelectionView: View {
    let totalPosts: Int
    @Binding var selectedGridType: MyProfileView.GridType?
    @Binding var selectedPosts: [Post]
    @Binding var showingGridSelection: Bool
    @Binding var showingPostSelection: Bool
    @State private var tempSelectedGridType: MyProfileView.GridType?

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("グリッドを選択")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: {
                        selectedGridType = nil
                        selectedPosts = []
                        showingGridSelection = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Text("全 \(totalPosts) 投稿")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))

                // Grid options
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(MyProfileView.GridType.availableTypes) { gridType in
                            let isAvailable = totalPosts >= gridType.count
                            let isSelected = tempSelectedGridType?.count == gridType.count

                            Button(action: {
                                if isAvailable {
                                    tempSelectedGridType = gridType
                                }
                            }) {
                                VStack(spacing: 8) {
                                    Text(gridType.displayText)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(isAvailable ? .white : .white.opacity(0.3))

                                    // Mini preview grid
                                    VStack(spacing: 2) {
                                        ForEach(0..<gridType.rows, id: \.self) { _ in
                                            HStack(spacing: 2) {
                                                ForEach(0..<gridType.columns, id: \.self) { _ in
                                                    Rectangle()
                                                        .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                                        .frame(width: 8, height: 8)
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isAvailable ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            isSelected ?
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color(hex: "cc208e"), Color(hex: "6713d2")]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ) :
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.white.opacity(isAvailable ? 0.3 : 0.1)]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: isSelected ? 3 : 1
                                        )
                                )
                            }
                            .disabled(!isAvailable)
                        }
                    }
                }

                // OK button
                if tempSelectedGridType != nil {
                    Button(action: {
                        selectedGridType = tempSelectedGridType
                        showingGridSelection = false
                        showingPostSelection = true
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
            }
            .padding(24)
        }
    }
}

// MARK: - Post Selection View
struct PostSelectionView: View {
    let posts: [Post]
    let gridType: MyProfileView.GridType
    @Binding var selectedPosts: [Post]
    @Binding var selectedGridType: MyProfileView.GridType?
    @Binding var showingPostSelection: Bool
    @Binding var isArtworkOnlyMode: Bool
    @Binding var screenshotMode: Bool

    @State private var localPosts: [Post] = []

    var body: some View {
        let spacing: CGFloat = 2
        let screenWidth = UIScreen.main.bounds.width
        let itemWidth = (screenWidth - spacing * 2 - 32) / 3  // 3 columns, 16px padding on each side

        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("投稿を選択")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text("\(selectedPosts.count)/\(gridType.count)")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Button(action: {
                        selectedPosts = []
                        selectedGridType = nil
                        showingPostSelection = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal)

                // Posts grid (3 columns) - Use regular VGrid instead of LazyVGrid to avoid cancellation issues
                ScrollView {
                    let columns = Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: 3)
                    LazyVStack(spacing: 0) {
                        ForEach(0..<Int(ceil(Double(localPosts.count) / 3.0)), id: \.self) { rowIndex in
                            HStack(spacing: spacing) {
                                ForEach(0..<3, id: \.self) { colIndex in
                                    let index = rowIndex * 3 + colIndex
                                    if index < localPosts.count {
                                        let post = localPosts[index]
                                        Button(action: {
                                            togglePostSelection(post)
                                        }) {
                                            ZStack(alignment: .topTrailing) {
                                                ArtworkImageView(
                                                    artworkUrl: post.artworkUrl,
                                                    placeholder: "photo",
                                                    width: itemWidth,
                                                    height: itemWidth
                                                )
                                                .frame(width: itemWidth, height: itemWidth)
                                                .clipped()

                                                // Selection indicator
                                                if let selectedIndex = selectedPosts.firstIndex(where: { $0.id == post.id }) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(Color.purple)
                                                            .frame(width: 28, height: 28)

                                                        Text("\(selectedIndex + 1)")
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundColor(.white)
                                                    }
                                                    .padding(8)
                                                }
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    } else {
                                        Color.clear
                                            .frame(width: itemWidth, height: itemWidth)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Bottom button
                if selectedPosts.count == gridType.count {
                    Button(action: {
                        showingPostSelection = false
                        isArtworkOnlyMode = true
                        screenshotMode = true
                    }) {
                        Text("スクショ画面へ")
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
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .onAppear {
            // 親Viewの再レンダリングの影響を受けないよう、postsをローカルにコピー
            if localPosts.isEmpty {
                localPosts = posts
            }
        }
    }

    private func togglePostSelection(_ post: Post) {
        if let index = selectedPosts.firstIndex(where: { $0.id == post.id }) {
            selectedPosts.remove(at: index)
        } else if selectedPosts.count < gridType.count {
            selectedPosts.append(post)
        }
    }
}

// MARK: - Dynamic Artwork Grid
struct DynamicArtworkGrid: View {
    let posts: [Post]
    let columns: Int
    let rows: Int

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let totalWidth = geometry.size.width
            let itemWidth = (totalWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                    ForEach(posts.prefix(columns * rows)) { post in
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
                .padding(.bottom, 100)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - ViewModel
@MainActor
class MyProfileViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var channels: [Channel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showEditChannelSheet = false
    @Published var editingChannel: Channel?
    @Published var editingChannelName: String = ""

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
                    // 投稿削除後、リストを再読み込みして最新状態に更新
                    await self?.loadPosts(forceRefresh: true)
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

        // forceRefreshがtrueの場合はキャッシュをスキップ
        if !forceRefresh {
            if let lastFetch = lastFetchTime {
                let elapsed = Date().timeIntervalSince(lastFetch)
                if elapsed < cacheValidDuration && !posts.isEmpty {
                    return
                }
            }
        }

        errorMessage = nil

        do {
            // 自分の投稿を取得（新しい順）
            let (fetchedPosts, _) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 50)
            posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
            lastFetchTime = Date()
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

    func updateChannelName() async {
        guard let channelId = editingChannel?.id,
              !editingChannelName.isEmpty else {
            print("❌ Invalid channel data for update")
            return
        }

        do {
            try await FirestoreChannelManager.shared.updateChannel(channelId: channelId, name: editingChannelName)

            // ローカルでチャンネル名を更新
            if let index = channels.firstIndex(where: { $0.id == channelId }) {
                channels[index].name = editingChannelName
            }

            // シートを閉じる
            showEditChannelSheet = false
            editingChannel = nil
            editingChannelName = ""

            print("✅ Channel name updated successfully")
        } catch {
            errorMessage = "チャンネル名の更新に失敗しました"
            print("❌ Failed to update channel name: \(error)")
        }
    }
}

// MARK: - Edit Channel Name Sheet
struct EditChannelNameSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var channelName: String
    let onSave: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("チャンネル名を編集")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("新しいチャンネル名を入力してください")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    TextField("チャンネル名", text: $channelName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)

                    HStack(spacing: 12) {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("キャンセル")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(12)
                        }

                        Button(action: {
                            onSave()
                            dismiss()
                        }) {
                            Text("保存")
                                .font(.headline)
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
                        .disabled(channelName.isEmpty)
                        .opacity(channelName.isEmpty ? 0.5 : 1.0)
                    }
                }
                .padding(24)
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.height(300)])
    }
}
