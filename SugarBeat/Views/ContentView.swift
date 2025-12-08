import SwiftUI
import MusicKit

// MARK: - アプリ全体のテーマカラー設定
/// ここを変更するだけで、アプリ全体の色が変わります
enum AppTheme {
    // MARK: - グラデーションカラー設定（6桁のHEXコードで指定）
    // 色を変えたい場合はここの値を変更してください

    /// グラデーション開始色（明るい方）
    static let gradientStartHex = "cc208e"  // ワインレッド（明）

    /// グラデーション終了色（暗い方）
    static let gradientEndHex = "6713d2"    // ワインレッド（暗）

    // MARK: - 計算プロパティ（変更不要）

    /// グラデーション開始色
    static var gradientStartColor: Color {
        Color(hex: gradientStartHex)
    }

    /// グラデーション終了色
    static var gradientEndColor: Color {
        Color(hex: gradientEndHex)
    }

    /// 横方向のグラデーション
    static var horizontalGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 縦方向のグラデーション
    static var verticalGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// リフレッシュインジケーター用の色
    static var tintColor: Color {
        gradientStartColor
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// 6桁のHEXコードからColorを生成
    /// 例: Color(hex: "FF5733")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @State private var selectedTab = 1 // 実際のタブは1から始まる（0と4はダミー）
    @State private var refreshTrigger = false
    @State private var showingCreatePost = false
    @State private var showingLoginPrompt = false  // ログイン必要アラート
    @State private var showingLoginSheet = false   // ログイン画面シート
    @State private var showingUserSearch = false
    @State private var showingNotifications = false
    @State private var postCreated = false
    @State private var showingScreenshotTip = false
    @State private var unreadNotificationCount = 0
    @State private var showingSettings = false
    @State private var pendingPlayPostId: Int64? = nil
    @State private var showingUserProfileFromNotification = false
    @State private var userIdForProfile: Int64? = nil
    @State private var lastNotificationFetchTime: Date?

    // グラデーション紫
    private let purpleGradient = LinearGradient(
        gradient: Gradient(colors: [Color.blue, Color.purple]),
        startPoint: .leading,
        endPoint: .trailing
    )

    // グラデーション（AppThemeから取得）
    private var orangeGradient: LinearGradient {
        AppTheme.horizontalGradient
    }

    // タブ情報（実際のタブ）- 通知を削除、フォロー中の後にプロフィール
    private let tabs: [(name: String, icon: String)] = [
        ("音楽の発見", "sparkles"),
        ("フォロー中の投稿", "person.2.fill"),
        ("自分の投稿", "person.fill")
    ]

    // 表示用のタブインデックス（0-2）
    private var displayTabIndex: Int {
        switch selectedTab {
        case 0: return 2  // ダミー（プロフィール）
        case 4: return 0  // ダミー（発見）
        default: return selectedTab - 1
        }
    }

    var body: some View {
        ZStack {
            // スワイプ可能なページビュー（循環用にダミーページを追加）
            TabView(selection: $selectedTab) {
                // ダミー: プロフィール（左端からさらに左へスワイプ用）
                MyProfileView(pendingPlayPostId: $pendingPlayPostId)
                    .tag(0)

                // 実際のページ
                DiscoveryView()
                    .tag(1)

                FollowingFeedView()
                    .tag(2)

                MyProfileView(pendingPlayPostId: $pendingPlayPostId)
                    .tag(3)

                // ダミー: 発見（右端からさらに右へスワイプ用）
                DiscoveryView()
                    .tag(4)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onChange(of: selectedTab) { newValue in
                // ダミーページに到達したら実際のページにジャンプ
                if newValue == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.none) {
                            selectedTab = 3 // プロフィール
                        }
                    }
                } else if newValue == 4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.none) {
                            selectedTab = 1 // 発見
                        }
                    }
                }
            }

            // 上部: タブ名インジケーター（スクショモード以外で表示）- 左上配置
            if !screenshotMode.isScreenshotMode {
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: tabs[displayTabIndex].icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(tabs[displayTabIndex].name)
                                .font(.system(size: 14, weight: .bold))

                            // 自分の投稿タブの場合は設定ボタンを表示
                            if displayTabIndex == 2 && authManager.isAuthenticated {
                                Button(action: {
                                    showingSettings = true
                                }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            orangeGradient
                                .opacity(0.9)
                        )
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8) // アプリ上部に配置

                    Spacer()
                }
            }

            // スクショモードのヒントモーダル
            if showingScreenshotTip {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingScreenshotTip = false
                        // 音楽を停止してスクショモードに入る
                        PlaybackStateManager.shared.stopPlayback()
                        MusicKitManager.shared.stopPreview()
                        screenshotMode.isScreenshotMode = true
                        print("📸 Screenshot mode enabled (tap on overlay)")
                    }

                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button(action: {
                            showingScreenshotTip = false
                            // 音楽を停止してスクショモードに入る
                            PlaybackStateManager.shared.stopPlayback()
                            MusicKitManager.shared.stopPreview()
                            screenshotMode.isScreenshotMode = true
                            print("📸 Screenshot mode enabled (X button)")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Image(systemName: "camera.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)

                    Text("スクショを撮って\nSNSに投稿しよう！")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.9))
                )
                .padding(.horizontal, 40)
            }

            // 下部のインジケーターとボタン
            // 下部バー（スクショモード以外で表示）
            if !screenshotMode.isScreenshotMode {
                VStack {
                    Spacer()

                    // カスタムインジケーター（ボタン群のみ、タブ名は上部に移動）
                    VStack(spacing: 6) {
                        // ボタン群とインジケーター
                        HStack(spacing: 0) {
                            // 左側: 投稿ボタン + スクショボタン
                            HStack(spacing: 12) {
                                Button(action: {
                                    if !authManager.isAuthenticated {
                                        showingLoginPrompt = true
                                    } else {
                                        showingCreatePost = true
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(orangeGradient)
                                }

                                Button(action: {
                                    showingScreenshotTip = true
                                }) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.leading, 16)

                            Spacer()

                            // 中央: ドットインジケーター
                            HStack(spacing: 8) {
                                ForEach(0..<tabs.count, id: \.self) { index in
                                    Circle()
                                        .fill(displayTabIndex == index ? orangeGradient : LinearGradient(colors: [Color.white.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 8, height: 8)
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                selectedTab = index + 1
                                            }
                                        }
                                }
                            }

                            Spacer()

                            // 右側: ユーザー検索ボタン + 通知ボタン
                            HStack(spacing: 12) {
                                Button(action: {
                                    if !authManager.isAuthenticated {
                                        showingLoginPrompt = true
                                    } else {
                                        showingUserSearch = true
                                    }
                                }) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }

                                Button(action: {
                                    if !authManager.isAuthenticated {
                                        showingLoginPrompt = true
                                    } else {
                                        showingNotifications = true
                                    }
                                }) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "bell.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white)

                                        // 通知バッジ
                                        if unreadNotificationCount > 0 {
                                            Text(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.red)
                                                .clipShape(Capsule())
                                                .offset(x: 8, y: -8)
                                        }
                                    }
                                }
                            }
                            .padding(.trailing, 16)
                        }
                    }
                    .frame(height: 50)
                    .background(Color.black.opacity(0.7))
                }
            }
        }
        .sheet(isPresented: $showingCreatePost) {
            refreshTrigger.toggle()
        } content: {
            CreatePostView(postCreated: $postCreated)
        }
        .alert("ログインが必要です", isPresented: $showingLoginPrompt) {
            Button("はい") {
                showingLoginSheet = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この機能を使用するにはログインが必要です")
        }
        .sheet(isPresented: $showingLoginSheet) {
            LoginView()
        }
        .sheet(isPresented: $showingUserSearch) {
            UserSearchView()
        }
        .sheet(isPresented: $showingNotifications, onDismiss: {
            // 通知を閉じたら未読カウントをリセット
            Task {
                await loadUnreadNotificationCount(forceRefresh: true)
            }
        }) {
            NavigationStack {
                NotificationsView()
                    .navigationTitle("通知")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") {
                                showingNotifications = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ProfileView()
                .environmentObject(authManager)
        }
        .task {
            await loadUnreadNotificationCount(forceRefresh: true)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadUnreadNotificationCount()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Foundation.Notification.Name("ReloadUnreadCounts"))) { _ in
            Task {
                await loadUnreadNotificationCount(forceRefresh: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayPostInMyProfile"))) { notification in
            if let postId = notification.userInfo?["postId"] as? Int64 {
                // Switch to MyProfile tab (tab index 3)
                selectedTab = 3
                // Store the postId to play
                pendingPlayPostId = postId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserProfile"))) { notification in
            if let userId = notification.userInfo?["userId"] as? Int64 {
                userIdForProfile = userId
                showingUserProfileFromNotification = true
            }
        }
        .sheet(isPresented: $showingUserProfileFromNotification) {
            if let userId = userIdForProfile {
                UserProfileView(userId: userId)
                    .environmentObject(authManager)
            }
        }
    }

    private func loadUnreadNotificationCount(forceRefresh: Bool = false) async {
        guard authManager.isAuthenticated else {
            unreadNotificationCount = 0
            return
        }

        // キャッシュが有効な場合はスキップ（30秒以内）
        if !forceRefresh, let lastFetch = lastNotificationFetchTime {
            let elapsed = Date().timeIntervalSince(lastFetch)
            if elapsed < 30 {
                return
            }
        }

        do {
            unreadNotificationCount = try await APIClient.shared.getUnreadNotificationCount()
            lastNotificationFetchTime = Date()
        } catch {
            print("Failed to load unread notification count: \(error)")
        }
    }
}


struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = CreatePostViewModel()
    @FocusState private var isCommentFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @Binding var postCreated: Bool

    var body: some View {
        NavigationStack {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Fixed header with close button and search bar
                VStack(spacing: 12) {
                    // Close button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Text("新規音楽紹介")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        // Placeholder for symmetry
                        Color.clear.frame(width: 28, height: 28)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Search bar - Fixed position
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.6))
                            TextField("曲名、アーティスト名で検索", text: $viewModel.searchQuery)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .focused($isSearchFocused)
                                .onSubmit {
                                    Task {
                                        await viewModel.performSearch()
                                    }
                                }
                            if !viewModel.searchQuery.isEmpty {
                                Button(action: { viewModel.searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)

                        // 検索ボタン
                        Button(action: {
                            isSearchFocused = false
                            Task {
                                await viewModel.performSearch()
                            }
                        }) {
                            Text("検索")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.searchQuery.isEmpty || viewModel.isSearching)
                    }
                    .padding(.horizontal)
                }
                .background(Color.clear)
                .padding(.bottom, 8)

                // Scrollable content area
                if viewModel.isSearching {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else if !viewModel.searchResults.isEmpty {
                    // Search results
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.searchResults, id: \.id) { song in
                                Button(action: {
                                    Task {
                                        await viewModel.selectSong(song)
                                    }
                                }) {
                                    MusicKitSearchRow(song: song)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let selectedSong = viewModel.selectedSong {
                    // Selected song and post creation
                    ScrollView {
                    VStack(spacing: 16) {
                        // Album artwork and song info
                        HStack(spacing: 12) {
                            if let artwork = selectedSong.artwork {
                                AsyncImage(url: artwork.url(width: 80, height: 80)) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                    case .failure:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                    @unknown default:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedSong.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                Text(selectedSong.artistName)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)

                        // Preview loading indicator
                        if viewModel.isFetchingPreview {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("プレビューを取得中...")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.vertical, 8)
                        }

                        // Play/Stop button
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
                        .padding(.horizontal)

                        // Comment field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("コメント")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            ZStack(alignment: .topLeading) {
                                Color(.systemGray6)
                                    .cornerRadius(8)

                                if viewModel.comment.isEmpty {
                                    Text("最低一文字必要です")
                                        .font(.body)
                                        .foregroundColor(Color(.systemGray3))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                }

                                TextEditor(text: $viewModel.comment)
                                    .frame(height: 80)
                                    .padding(8)
                                    .background(Color.clear)
                                    .cornerRadius(8)
                                    .focused($isCommentFocused)
                                    .scrollContentBackground(.hidden)
                                    .simultaneousGesture(
                                        TapGesture()
                                            .onEnded { _ in
                                                if isCommentFocused {
                                                    isCommentFocused = false
                                                }
                                            }
                                    )
                                    .toolbar {
                                        ToolbarItemGroup(placement: .keyboard) {
                                            Spacer()
                                            Button("完了") {
                                                isCommentFocused = false
                                            }
                                        }
                                    }
                            }
                            .frame(height: 80)
                        }
                        .padding(.horizontal)

                        // Post button
                        Button(action: {
                            Task {
                                await viewModel.createPost()
                                if viewModel.postCreated {
                                    postCreated = true
                                    dismiss()
                                }
                            }
                        }) {
                            if viewModel.isPosting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("この内容で紹介する")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                        }
                        .disabled(viewModel.isPosting || viewModel.isFetchingPreview || viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity((viewModel.isPosting || viewModel.isFetchingPreview || viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .padding(.top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("曲を検索して紹介")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxHeight: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
            }

        }
        .navigationBarHidden(true)
        }
        .onAppear {
            Task {
                await viewModel.warmupSearch()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct MusicKitSearchRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                AsyncImage(url: artwork.url(width: 50, height: 50)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    @unknown default:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .foregroundColor(.white)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                if let albumTitle = song.albumTitle {
                    Text(albumTitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
