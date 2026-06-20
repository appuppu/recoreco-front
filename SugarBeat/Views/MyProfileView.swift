import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    // Screenshot grid selection
    @State private var showingGridSelection = false
    @State private var showingPostSelection = false
    @State private var selectedGridType: GridType?
    @State private var selectedPosts: [Post] = []


    struct GridType: Identifiable {
        let id = UUID()
        let count: Int
        let rows: Int
        let columns: Int
        let isOriginalGrid: Bool

        init(count: Int, rows: Int, columns: Int, isOriginalGrid: Bool = false) {
            self.count = count
            self.rows = rows
            self.columns = columns
            self.isOriginalGrid = isOriginalGrid
        }

        var displayText: String {
            if isOriginalGrid {
                return "オリジナル(\(count))"
            }
            return "\(count)(\(columns)×\(rows))"
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
            GridType(count: 42, rows: 7, columns: 6),
            GridType(count: 47, rows: 0, columns: 0, isOriginalGrid: true)
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
                // ヘッダー
                if let currentUser = authManager.currentUser {
                    userInfoHeader(user: currentUser)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(Color.black)
                }

                // コンテンツ
                Group {
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
                            isLoadingMore: viewModel.isLoadingMore,
                            onRefresh: {
                                await viewModel.loadPosts(forceRefresh: true)
                            },
                            onLoadMore: {
                                await viewModel.loadMorePosts()
                            },
                            topPadding: 0
                        )
                        .environmentObject(authManager)
                        .id("posts-grid") // 投稿タブのときは固定のID
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artworkOnlyGrid: some View {
        if let gridType = selectedGridType, !selectedPosts.isEmpty {
            DynamicArtworkGrid(posts: selectedPosts, columns: gridType.columns, rows: gridType.rows, gridType: gridType)
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
            DynamicArtworkGrid(posts: viewModel.posts, columns: 3, rows: 3, gridType: nil)
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
                            // 投稿数を取得
                            Task {
                                await viewModel.fetchPostCount()
                            }
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
                if authManager.isAuthenticated {
                    Task {
                        // 投稿が空の場合、または最後のfetchから30秒以上経過している場合はリロード
                        if viewModel.posts.isEmpty {
                            await viewModel.loadPosts()
                        } else if viewModel.shouldRefreshPosts() {
                            await viewModel.loadPosts(forceRefresh: true)
                        }
                    }
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
                    totalPosts: viewModel.postCount,
                    selectedGridType: $selectedGridType,
                    selectedPosts: $selectedPosts,
                    showingGridSelection: $showingGridSelection,
                    showingPostSelection: $showingPostSelection
                )
            }
            .fullScreenCover(isPresented: $showingPostSelection) {
                if let gridType = selectedGridType {
                    PostSelectionView(
                        viewModel: viewModel,
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
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.5))
                        )
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
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            print("📏 [Header] Profile info section height: \(geo.size.height)")
                        }
                }
            )

        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        print("📏 [Header] Total VStack height (before padding): \(geo.size.height)")
                    }
            }
        )
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

// MARK: - Original Grid Mini Preview
struct OriginalGridMiniPreview: View {
    let isAvailable: Bool

    var body: some View {
        let cellSize: CGFloat = 6
        let spacing: CGFloat = 1.5
        let mergedSize = cellSize * 2 + spacing

        VStack(spacing: spacing) {
            // Rows 1-2: 6列グリッド with merged cell
            HStack(alignment: .top, spacing: spacing) {
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }

                Rectangle()
                    .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                    .frame(width: mergedSize, height: mergedSize)

                VStack(spacing: spacing) {
                    Rectangle()
                        .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                        .frame(width: cellSize, height: cellSize)
                    Rectangle()
                        .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                        .frame(width: cellSize, height: cellSize)
                }
            }

            // Rows 3-4: 5列グリッド with merged cell
            HStack(alignment: .top, spacing: spacing) {
                Rectangle()
                    .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                    .frame(width: mergedSize, height: mergedSize)

                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }

            // Row 5: 6列 single row
            HStack(spacing: spacing) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(isAvailable ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                        .frame(width: cellSize, height: cellSize)
                }
            }
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
                                    if gridType.isOriginalGrid {
                                        OriginalGridMiniPreview(isAvailable: isAvailable)
                                    } else {
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
    @ObservedObject var viewModel: MyProfileViewModel
    let gridType: MyProfileView.GridType
    @Binding var selectedPosts: [Post]
    @Binding var selectedGridType: MyProfileView.GridType?
    @Binding var showingPostSelection: Bool
    @Binding var isArtworkOnlyMode: Bool
    @Binding var screenshotMode: Bool

    init(viewModel: MyProfileViewModel, gridType: MyProfileView.GridType, selectedPosts: Binding<[Post]>, selectedGridType: Binding<MyProfileView.GridType?>, showingPostSelection: Binding<Bool>, isArtworkOnlyMode: Binding<Bool>, screenshotMode: Binding<Bool>) {
        self.viewModel = viewModel
        self.gridType = gridType
        self._selectedPosts = selectedPosts
        self._selectedGridType = selectedGridType
        self._showingPostSelection = showingPostSelection
        self._isArtworkOnlyMode = isArtworkOnlyMode
        self._screenshotMode = screenshotMode
        print("🎬 [PostSelectionView] Initialized with \(viewModel.posts.count) posts")
    }

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
                        ForEach(0..<Int(ceil(Double(viewModel.posts.count) / 3.0)), id: \.self) { rowIndex in
                            HStack(spacing: spacing) {
                                ForEach(0..<3, id: \.self) { colIndex in
                                    let index = rowIndex * 3 + colIndex
                                    if index < viewModel.posts.count {
                                        let post = viewModel.posts[index]
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

                        // 追加読み込みトリガー
                        if !viewModel.isLoadingMore && viewModel.posts.count < viewModel.postCount {
                            Color.clear
                                .frame(height: 50)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMorePosts()
                                    }
                                }
                        }

                        // ローディングインジケータ
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(.white)
                                    .padding()
                                Spacer()
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
    let gridType: MyProfileView.GridType?

    var body: some View {
        if gridType?.isOriginalGrid == true {
            // オリジナルグリッド: PostGridViewの複雑なレイアウトを使用
            OriginalGridLayoutView(posts: posts)
        } else {
            // 通常グリッド: 均等な格子レイアウト
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
}

// MARK: - Original Grid Layout View
struct OriginalGridLayoutView: View {
    let posts: [Post]

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let screenWidth = geometry.size.width

            // セルサイズの計算
            let columns6Width = (screenWidth - spacing * 5) / 6
            let columns5Width = (screenWidth - spacing * 4) / 5
            let mergedCellWidth6 = columns6Width * 2 + spacing
            let mergedCellHeight6 = columns6Width * 2 + spacing
            let mergedCellWidth5 = columns5Width * 2 + spacing
            let mergedCellHeight5 = columns5Width * 2 + spacing

            ScrollView(showsIndicators: false) {
                VStack(spacing: spacing) {
                    // Rows 1-2: 6列グリッド with merged cell (9投稿: indices 0-8)
                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(0..<3, id: \.self) { index in
                                    artworkCell(index: index, width: columns6Width, height: columns6Width)
                                }
                            }
                            HStack(spacing: spacing) {
                                ForEach(5..<8, id: \.self) { index in
                                    artworkCell(index: index, width: columns6Width, height: columns6Width)
                                }
                            }
                        }

                        artworkCell(index: 3, width: mergedCellWidth6, height: mergedCellHeight6)

                        VStack(spacing: spacing) {
                            artworkCell(index: 4, width: columns6Width, height: columns6Width)
                            artworkCell(index: 8, width: columns6Width, height: columns6Width)
                        }
                    }

                    // Rows 3-4: 5列グリッド with merged cell (7投稿: indices 9-15)
                    HStack(alignment: .top, spacing: spacing) {
                        artworkCell(index: 9, width: mergedCellWidth5, height: mergedCellHeight5)

                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(10..<13, id: \.self) { index in
                                    artworkCell(index: index, width: columns5Width, height: columns5Width)
                                }
                            }
                            HStack(spacing: spacing) {
                                ForEach(13..<16, id: \.self) { index in
                                    artworkCell(index: index, width: columns5Width, height: columns5Width)
                                }
                            }
                        }
                    }

                    // Row 5: 6列 single row (6投稿: indices 16-21)
                    HStack(spacing: spacing) {
                        ForEach(16..<22, id: \.self) { index in
                            artworkCell(index: index, width: columns6Width, height: columns6Width)
                        }
                    }

                    // Rows 6-7: 6列グリッド with merged cell (9投稿: indices 22-30)
                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(22..<25, id: \.self) { index in
                                    artworkCell(index: index, width: columns6Width, height: columns6Width)
                                }
                            }
                            HStack(spacing: spacing) {
                                ForEach(27..<30, id: \.self) { index in
                                    artworkCell(index: index, width: columns6Width, height: columns6Width)
                                }
                            }
                        }

                        artworkCell(index: 25, width: mergedCellWidth6, height: mergedCellHeight6)

                        VStack(spacing: spacing) {
                            artworkCell(index: 26, width: columns6Width, height: columns6Width)
                            artworkCell(index: 30, width: columns6Width, height: columns6Width)
                        }
                    }

                    // Rows 8-9: 5列グリッド with merged cell (7投稿: indices 31-37)
                    HStack(alignment: .top, spacing: spacing) {
                        artworkCell(index: 31, width: mergedCellWidth5, height: mergedCellHeight5)

                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(32..<35, id: \.self) { index in
                                    artworkCell(index: index, width: columns5Width, height: columns5Width)
                                }
                            }
                            HStack(spacing: spacing) {
                                ForEach(35..<38, id: \.self) { index in
                                    artworkCell(index: index, width: columns5Width, height: columns5Width)
                                }
                            }
                        }
                    }

                    // Rows 10-11: 6列グリッド with merged cell (9投稿: indices 38-46)
                    HStack(alignment: .top, spacing: spacing) {
                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(38..<41, id: \.self) { index in
                                    artworkCell(index: index, width: columns6Width, height: columns6Width)
                                }
                            }
                            HStack(spacing: spacing) {
                                ForEach(43..<46, id: \.self) { index in
                                    artworkCell(index: index, width: columns6Width, height: columns6Width)
                                }
                            }
                        }

                        artworkCell(index: 41, width: mergedCellWidth6, height: mergedCellHeight6)

                        VStack(spacing: spacing) {
                            artworkCell(index: 42, width: columns6Width, height: columns6Width)
                            artworkCell(index: 46, width: columns6Width, height: columns6Width)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func artworkCell(index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < posts.count, let artworkUrl = posts[index].artworkUrl, let url = URL(string: artworkUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: width, height: height)
            .clipped()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(width: width, height: height)
        }
    }
}

// MARK: - ViewModel
@MainActor
class MyProfileViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var postCount: Int = 0

    private var lastFetchTime: Date?
    private let cacheValidDuration: TimeInterval = 30 // 30秒キャッシュ
    private var lastDocument: DocumentSnapshot?
    private var hasMorePosts = true

    init() {
        // 投稿完了通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("📥 [MyProfileViewModel] Received postCreated notification, reloading posts...")
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

        // Reset pagination state on initial load
        lastDocument = nil
        hasMorePosts = true

        do {
            // 自分の投稿を取得（新しい順）
            print("🔄 [MyProfileViewModel] Fetching posts for userId: \(currentUserId), forceRefresh: \(forceRefresh)")
            let (fetchedPosts, lastDoc) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 20)
            posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
            lastDocument = lastDoc
            hasMorePosts = fetchedPosts.count >= 20
            lastFetchTime = Date()
            print("✅ [MyProfileViewModel] Fetched \(posts.count) posts for user, hasMore: \(hasMorePosts)")
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

    func loadMorePosts() async {
        guard !isLoadingMore, hasMorePosts, let lastDoc = lastDocument else {
            print("⏭️ [MyProfileViewModel] Skip loadMore - isLoadingMore: \(isLoadingMore), hasMore: \(hasMorePosts), lastDoc: \(lastDocument != nil)")
            return
        }

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("⚠️ [MyProfileViewModel] loadMorePosts: User not authenticated")
            return
        }

        isLoadingMore = true
        print("📄 [MyProfileViewModel] Loading more posts from lastDocument...")

        do {
            let (fetchedPosts, lastDoc) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 20, lastDocument: lastDoc)

            // Append new posts to existing posts
            posts.append(contentsOf: fetchedPosts.sorted { $0.createdAt > $1.createdAt })
            lastDocument = lastDoc
            hasMorePosts = fetchedPosts.count >= 20

            print("✅ [MyProfileViewModel] Loaded \(fetchedPosts.count) more posts. Total: \(posts.count), hasMore: \(hasMorePosts)")
        } catch {
            print("❌ [MyProfileViewModel] Failed to load more posts: \(error)")
        }

        isLoadingMore = false
    }

    func shouldRefreshPosts() -> Bool {
        guard let lastFetch = lastFetchTime else {
            return true // まだfetchしていない
        }
        let elapsed = Date().timeIntervalSince(lastFetch)
        return elapsed >= cacheValidDuration
    }

    func fetchPostCount() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("⚠️ [MyProfileViewModel] fetchPostCount: User not authenticated")
            return
        }

        do {
            let user = try await FirestoreUserManager.shared.getUser(userId: currentUserId, useCache: false, fetchCounts: true)
            postCount = user.postCount ?? 0
            print("✅ [MyProfileViewModel] Fetched post count: \(postCount)")
        } catch {
            print("❌ [MyProfileViewModel] Failed to fetch post count: \(error)")
            // Fallback to loaded posts count
            postCount = posts.count
        }
    }
}

// MARK: - HeaderHeightPreferenceKey
struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
