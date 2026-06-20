import SwiftUI
import FirebaseAuth
import UIKit

// MARK: - ScrollableView (UIScrollViewラッパー)

/// UIScrollViewをラップしたSwiftUIビュー（スクロールオフセット検出機能付き）
struct ScrollableView<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let onScroll: (CGFloat) -> Void
    let resetTrigger: Int // スクロール位置をリセットするトリガー

    init(@ViewBuilder content: () -> Content, onScroll: @escaping (CGFloat) -> Void, resetTrigger: Int = 0) {
        self.content = content()
        self.onScroll = onScroll
        self.resetTrigger = resetTrigger
    }

    func makeUIViewController(context: Context) -> ScrollViewController<Content> {
        let viewController = ScrollViewController(content: content, onScroll: onScroll)
        return viewController
    }

    func updateUIViewController(_ uiViewController: ScrollViewController<Content>, context: Context) {
        uiViewController.updateContent(content)

        // resetTriggerが変わったらスクロール位置をリセット
        if context.coordinator.lastResetTrigger != resetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            uiViewController.resetScrollPosition()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastResetTrigger: Int = 0
    }
}

class ScrollViewController<Content: View>: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var hostingController: UIHostingController<Content>?
    private let onScroll: (CGFloat) -> Void
    private var hasInitiallyResetScroll = false // 初回スクロールリセットフラグ

    init(content: Content, onScroll: @escaping (CGFloat) -> Void) {
        self.onScroll = onScroll
        super.init(nibName: nil, bundle: nil)

        // ScrollViewのセットアップ
        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        view.addSubview(scrollView)

        // ホスティングコントローラーのセットアップ
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        scrollView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        hostingController = hosting

        // 初期スクロールオフセット(0)を通知
        onScroll(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // frameベースのレイアウト
        scrollView.frame = view.bounds

        if let hostingView = hostingController?.view {
            let contentSize = hostingController?.sizeThatFits(in: view.bounds.size) ?? view.bounds.size
            hostingView.frame = CGRect(origin: .zero, size: contentSize)
            scrollView.contentSize = contentSize

            print("📐 [ScrollViewController] scrollView.frame: \(scrollView.frame)")
            print("📐 [ScrollViewController] contentSize: \(contentSize)")
            print("📐 [ScrollViewController] contentOffset: \(scrollView.contentOffset)")

            // 初回レイアウト完了後、スクロール位置を0に確実に設定（一度だけ）
            if !hasInitiallyResetScroll && scrollView.contentSize.height > 0 {
                scrollView.contentOffset = .zero
                onScroll(0)
                hasInitiallyResetScroll = true
                print("📐 [ScrollViewController] Initial scroll reset to 0")
            }
        }
    }

    func updateContent(_ newContent: Content) {
        hostingController?.rootView = newContent
        view.setNeedsLayout()
    }

    func resetScrollPosition() {
        print("🔄 [ScrollViewController] resetScrollPosition called")
        scrollView.setContentOffset(.zero, animated: false)
        onScroll(0)
        print("🔄 [ScrollViewController] Scroll reset to zero, onScroll(0) called")
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y
        onScroll(max(0, offset))
    }
}

// MARK: - PostGridView

/// 再利用可能な投稿グリッドレイアウト
/// - 最初の投稿を大きなセルで表示
/// - 残りの投稿をグリッドレイアウトで表示
struct PostGridView: View {
    let posts: [Post]
    @Binding var showingLoginPrompt: Bool
    var isScreenshotMode: Bool = false
    var showUserInfo: Bool = true // 大きいセルにユーザー情報を表示するか
    var isLoading: Bool = false // リフレッシュ中のローディング表示
    var isLoadingMore: Bool = false // 追加読み込み中のローディング表示
    var onRefresh: (() async -> Void)? = nil // リフレッシュコールバック
    var onLoadMore: (() async -> Void)? = nil // 追加読み込みコールバック
    var onScrollOffsetChange: ((CGFloat) -> Void)? = nil // スクロールオフセットコールバック
    var topPadding: CGFloat = 0 // 上部のパディング（ヘッダー用）
    var respectNavigationBar: Bool = false // NavigationBarの下に表示するかどうか
    var scrollResetTrigger: Int = 0 // スクロール位置をリセットするトリガー

    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @ObservedObject private var playbackState = PlaybackStateManager.shared
    @EnvironmentObject var authManager: AuthManager

    // Dynamic user info cache
    @State private var postUserCache: [String: User] = [:]  // postId -> User
    @State private var featuredCellKey = UUID() // Featured cellを強制再作成するためのキー

    /// 再生中の投稿（先頭以外で再生中の場合のみ）
    var playingPost: Post? {
        guard let playingPostId = playbackState.currentlyPlayingPostId,
              posts.count > 1,
              let playingPost = posts.first(where: { $0.id == playingPostId }),
              playingPost.id != posts.first?.id else {
            return nil
        }
        return playingPost
    }

    /// 表示する投稿（再生中の投稿があればそれ、なければ最初の投稿）
    var displayPost: Post? {
        playingPost ?? posts.first
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let spacing: CGFloat = 2
            let featuredHeight = screenWidth // 正方形
            let safeAreaTop = geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                Color.black

                if onScrollOffsetChange != nil {
                    // スクロール検出が必要な場合はScrollableViewを使用
                    ScrollableView(
                        content: {
                            LazyVStack(spacing: 0) {
                                // ヘッダー用のスペース
                                Color.clear
                                    .frame(height: topPadding)
                                    .onAppear {
                                        print("📏 [PostGridView] topPadding applied: \(topPadding)")
                                    }

                                // 一番上のグリッド: スクショモード時はユーザー情報、通常時は投稿
                                if screenshotMode.isScreenshotMode {
                                    // スクショモード: ユーザー情報セル
                                    UserInfoCell(width: screenWidth, height: featuredHeight)
                                        .environmentObject(authManager)
                                } else if let post = displayPost {
                                    // 通常モード: 投稿セル
                                    FeaturedPostCellSimple(
                                        post: post,
                                        width: screenWidth,
                                        height: featuredHeight,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode,
                                        showUserInfo: showUserInfo,
                                        safeAreaTop: safeAreaTop
                                    )
                                    .id("\(post.id ?? "nil")_\(featuredCellKey.uuidString)")
                                    .frame(width: screenWidth, height: featuredHeight)
                                }

                                // 残りのグリッド
                                if posts.count > 1 {
                                    gridLayout(posts: Array(posts.dropFirst()), screenWidth: screenWidth, spacing: spacing)
                                        .padding(.top, spacing)
                                }

                                // 追加読み込みインジケータ
                                if isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.white)
                                            .padding()
                                        Spacer()
                                    }
                                } else if onLoadMore != nil {
                                    Color.clear
                                        .frame(height: 50)
                                        .onAppear {
                                            Task {
                                                await onLoadMore?()
                                            }
                                        }
                                }
                            }
                            .padding(.bottom, 100)
                        },
                        onScroll: { offset in
                            onScrollOffsetChange?(offset)
                        },
                        resetTrigger: scrollResetTrigger
                    )
                    .id(scrollResetTrigger) // resetTriggerが変わったらScrollableViewを完全に再作成
                    .onAppear {
                        // 表示された時に必ずスクロール位置を0に通知
                        DispatchQueue.main.async {
                            onScrollOffsetChange?(0)
                        }
                    }
                } else {
                    // スクロール検出が不要な場合は通常のScrollViewを使用
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // ヘッダー用のスペース
                            Color.clear
                                .frame(height: topPadding)

                            // 一番上のグリッド
                            if screenshotMode.isScreenshotMode {
                                UserInfoCell(width: screenWidth, height: featuredHeight)
                                    .environmentObject(authManager)
                            } else if let post = displayPost {
                                FeaturedPostCellSimple(
                                    post: post,
                                    width: screenWidth,
                                    height: featuredHeight,
                                    showingLoginPrompt: $showingLoginPrompt,
                                    isScreenshotMode: screenshotMode.isScreenshotMode,
                                    showUserInfo: showUserInfo,
                                    safeAreaTop: safeAreaTop
                                )
                                .id("\(post.id ?? "nil")_\(featuredCellKey.uuidString)")
                                .frame(width: screenWidth, height: featuredHeight)
                            }

                            // 残りのグリッド
                            if posts.count > 1 {
                                gridLayout(posts: Array(posts.dropFirst()), screenWidth: screenWidth, spacing: spacing)
                                    .padding(.top, spacing)
                            }

                            // 追加読み込みインジケータ
                            if isLoadingMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(.white)
                                        .padding()
                                    Spacer()
                                }
                            } else if onLoadMore != nil {
                                Color.clear
                                    .frame(height: 50)
                                    .onAppear {
                                        Task {
                                            await onLoadMore?()
                                        }
                                    }
                            }
                        }
                        .padding(.bottom, 100)
                    }
                    .refreshable {
                        if let refresh = onRefresh {
                            await refresh()
                        }
                    }
                    .tint(.white)
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                if screenshotMode.isScreenshotMode {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        screenshotMode.isScreenshotMode = false
                                    }
                                }
                            }
                    )
                }

                // リフレッシュ中のローディングオーバーレイ（投稿が空の時のみ）
                if isLoading && posts.isEmpty {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
            .ignoresSafeArea(respectNavigationBar ? [] : .all)
        }
        .toolbar(screenshotMode.isScreenshotMode ? .hidden : .visible, for: .tabBar)
        .onAppear {
            // タブに戻ってきたときに画像を強制的に再読み込み
            featuredCellKey = UUID()
        }
        .onChange(of: displayPost?.id) { newPostId in
            // Featured cellを完全に再作成するためにキーを更新
            featuredCellKey = UUID()
        }
        .onChange(of: screenshotMode.isScreenshotMode) { _ in
            // スクショモードの切り替え時（特に終了時）にFeatured cellを再作成し、
            // アートワークがローディング状態のまま固まるのを防ぐ
            featuredCellKey = UUID()
        }
    }

    // MARK: - Grid Layout
    @ViewBuilder
    private func gridLayout(posts: [Post], screenWidth: CGFloat, spacing: CGFloat) -> some View {
        // セルサイズの計算
        let columns6Width = (screenWidth - spacing * 5) / 6
        let columns5Width = (screenWidth - spacing * 4) / 5
        let columns4Width = (screenWidth - spacing * 3) / 4

        // マージセルサイズ
        let mergedCellWidth6 = columns6Width * 2 + spacing
        let mergedCellHeight6 = columns6Width * 2 + spacing
        let mergedCellWidth5 = columns5Width * 2 + spacing
        let mergedCellHeight5 = columns5Width * 2 + spacing

        // 残りの投稿パターン用のセルサイズ
        let row34CellWidth = columns6Width
        let row34CellHeight = columns6Width
        let mergedCellWidth34 = mergedCellWidth6
        let mergedCellHeight34 = mergedCellHeight6
        let row12CellWidth = columns5Width
        let row12CellHeight = columns5Width
        let mergedCellWidth = mergedCellWidth5
        let mergedCellHeight = mergedCellHeight5

        let _ = print("🎨 [PostGridView.gridLayout] screenshotMode: \(screenshotMode.isScreenshotMode), posts.count: \(posts.count)")

        VStack(spacing: spacing) {
            // 投稿数が少ない場合、またはスクショモード時は単純な4列グリッドを使用
            if posts.count < 9 || screenshotMode.isScreenshotMode {
                let _ = print("🎨 [PostGridView.gridLayout] Using simple 4-column grid")
                // シンプルな4列グリッド（左詰め）
                let rowCount = (posts.count + 3) / 4
                let _ = print("🎨 [PostGridView.gridLayout] totalCells: \(posts.count), rowCount: \(rowCount)")
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<4, id: \.self) { col in
                            let index = row * 4 + col

                            if index < posts.count {
                                SmallPostCell(
                                    post: posts[index],
                                    width: columns4Width,
                                    height: columns4Width,
                                    showingLoginPrompt: $showingLoginPrompt,
                                    isScreenshotMode: screenshotMode.isScreenshotMode
                                )
                            } else {
                                Color.clear.frame(width: columns4Width, height: columns4Width)
                            }
                        }
                    }
                }
            } else {
                // 複雑なレイアウト（投稿が9個以上の場合）
                // Rows 1-2 (6 columns with merged cell) - 9 posts
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            ForEach(0..<3, id: \.self) { index in
                                if index < posts.count {
                                    SmallPostCell(
                                        post: posts[index],
                                        width: columns6Width,
                                        height: columns6Width,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode
                                    )
                                }
                            }
                        }
                        HStack(spacing: spacing) {
                            ForEach(5..<8, id: \.self) { index in
                                if index < posts.count {
                                    SmallPostCell(
                                        post: posts[index],
                                        width: columns6Width,
                                        height: columns6Width,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode
                                    )
                                } else {
                                    Color.clear.frame(width: columns6Width, height: columns6Width)
                                }
                            }
                        }
                    }

                    let index3 = screenshotMode.isScreenshotMode ? 2 : 3
                    if index3 < posts.count {
                        SmallPostCell(
                            post: posts[index3],
                            width: mergedCellWidth6,
                            height: mergedCellHeight6,
                            showingLoginPrompt: $showingLoginPrompt,
                            isScreenshotMode: screenshotMode.isScreenshotMode
                        )
                    }

                    VStack(spacing: spacing) {
                        let index4 = screenshotMode.isScreenshotMode ? 3 : 4
                        if index4 < posts.count {
                            SmallPostCell(
                                post: posts[index4],
                                width: columns6Width,
                                height: columns6Width,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode
                            )
                        } else {
                            Color.clear.frame(width: columns6Width, height: columns6Width)
                        }
                        let index8 = screenshotMode.isScreenshotMode ? 7 : 8
                        if index8 < posts.count {
                            SmallPostCell(
                                post: posts[index8],
                                width: columns6Width,
                                height: columns6Width,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode
                            )
                        } else {
                            Color.clear.frame(width: columns6Width, height: columns6Width)
                        }
                    }
                }

                // Rows 3-4 (5 columns with merged cell) - posts 9-15
                if posts.count > 9 {
                    HStack(alignment: .top, spacing: spacing) {
                        SmallPostCell(
                            post: posts[9],
                            width: mergedCellWidth5,
                            height: mergedCellHeight5,
                            showingLoginPrompt: $showingLoginPrompt,
                            isScreenshotMode: screenshotMode.isScreenshotMode
                        )

                        VStack(spacing: spacing) {
                            HStack(spacing: spacing) {
                                ForEach(10..<13, id: \.self) { index in
                                    if index < posts.count {
                                        SmallPostCell(
                                            post: posts[index],
                                            width: columns5Width,
                                            height: columns5Width,
                                            showingLoginPrompt: $showingLoginPrompt,
                                            isScreenshotMode: screenshotMode.isScreenshotMode
                                        )
                                    } else {
                                        Color.clear.frame(width: columns5Width, height: columns5Width)
                                    }
                                }
                            }
                            HStack(spacing: spacing) {
                                ForEach(13..<16, id: \.self) { index in
                                    if index < posts.count {
                                        SmallPostCell(
                                            post: posts[index],
                                            width: columns5Width,
                                            height: columns5Width,
                                            showingLoginPrompt: $showingLoginPrompt,
                                            isScreenshotMode: screenshotMode.isScreenshotMode
                                        )
                                    } else {
                                        Color.clear.frame(width: columns5Width, height: columns5Width)
                                    }
                                }
                            }
                        }
                    }
                }

                // Row 5: 6 columns single row - posts 16-21
                if posts.count > 16 {
                    HStack(spacing: spacing) {
                        ForEach(16..<22, id: \.self) { index in
                            if index < posts.count {
                                SmallPostCell(
                                    post: posts[index],
                                    width: columns6Width,
                                    height: columns6Width,
                                    showingLoginPrompt: $showingLoginPrompt,
                                    isScreenshotMode: screenshotMode.isScreenshotMode
                                )
                            } else {
                                Color.clear.frame(width: columns6Width, height: columns6Width)
                            }
                        }
                    }
                }
            }

            // Remaining posts: repeat pattern
            let remainingPosts = Array(posts.dropFirst(22))
            let blockSize = 22 // 9 + 7 + 6
            let blockCount = (remainingPosts.count + blockSize - 1) / blockSize

            ForEach(0..<blockCount, id: \.self) { blockIndex in
                let blockStartIndex = blockIndex * blockSize

                // First part: 6 columns x 2 rows with merged cell (9 posts)
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            ForEach(0..<3) { offset in
                                let index = blockStartIndex + offset
                                if index < remainingPosts.count {
                                    SmallPostCell(
                                        post: remainingPosts[index],
                                        width: row34CellWidth,
                                        height: row34CellHeight,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode
                                    )
                                } else {
                                    Color.clear.frame(width: row34CellWidth, height: row34CellHeight)
                                }
                            }
                        }

                        HStack(spacing: spacing) {
                            ForEach(5..<8) { offset in
                                let index = blockStartIndex + offset
                                if index < remainingPosts.count {
                                    SmallPostCell(
                                        post: remainingPosts[index],
                                        width: row34CellWidth,
                                        height: row34CellHeight,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode
                                    )
                                } else {
                                    Color.clear.frame(width: row34CellWidth, height: row34CellHeight)
                                }
                            }
                        }
                    }

                    let index3 = blockStartIndex + 3
                    if index3 < remainingPosts.count {
                        SmallPostCell(
                            post: remainingPosts[index3],
                            width: mergedCellWidth34,
                            height: mergedCellHeight34,
                            showingLoginPrompt: $showingLoginPrompt,
                            isScreenshotMode: screenshotMode.isScreenshotMode
                        )
                    } else {
                        Color.clear.frame(width: mergedCellWidth34, height: mergedCellHeight34)
                    }

                    VStack(spacing: spacing) {
                        let index4 = blockStartIndex + 4
                        if index4 < remainingPosts.count {
                            SmallPostCell(
                                post: remainingPosts[index4],
                                width: row34CellWidth,
                                height: row34CellHeight,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode
                            )
                        } else {
                            Color.clear.frame(width: row34CellWidth, height: row34CellHeight)
                        }

                        let index8 = blockStartIndex + 8
                        if index8 < remainingPosts.count {
                            SmallPostCell(
                                post: remainingPosts[index8],
                                width: row34CellWidth,
                                height: row34CellHeight,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode
                            )
                        } else {
                            Color.clear.frame(width: row34CellWidth, height: row34CellHeight)
                        }
                    }
                }

                // Second part: 5 columns x 2 rows with merged cell (7 posts)
                HStack(alignment: .top, spacing: spacing) {
                    let index9 = blockStartIndex + 9
                    if index9 < remainingPosts.count {
                        SmallPostCell(
                            post: remainingPosts[index9],
                            width: mergedCellWidth,
                            height: mergedCellHeight,
                            showingLoginPrompt: $showingLoginPrompt,
                            isScreenshotMode: screenshotMode.isScreenshotMode
                        )
                    } else {
                        Color.clear.frame(width: mergedCellWidth, height: mergedCellHeight)
                    }

                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            ForEach(10..<13) { offset in
                                let index = blockStartIndex + offset
                                if index < remainingPosts.count {
                                    SmallPostCell(
                                        post: remainingPosts[index],
                                        width: row12CellWidth,
                                        height: row12CellHeight,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode
                                    )
                                } else {
                                    Color.clear.frame(width: row12CellWidth, height: row12CellHeight)
                                }
                            }
                        }

                        HStack(spacing: spacing) {
                            ForEach(13..<16) { offset in
                                let index = blockStartIndex + offset
                                if index < remainingPosts.count {
                                    SmallPostCell(
                                        post: remainingPosts[index],
                                        width: row12CellWidth,
                                        height: row12CellHeight,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        isScreenshotMode: screenshotMode.isScreenshotMode
                                    )
                                } else {
                                    Color.clear.frame(width: row12CellWidth, height: row12CellHeight)
                                }
                            }
                        }
                    }
                }

                // Third part: 6 columns x 1 row (6 posts)
                HStack(spacing: spacing) {
                    ForEach(16..<22) { offset in
                        let index = blockStartIndex + offset
                        if index < remainingPosts.count {
                            SmallPostCell(
                                post: remainingPosts[index],
                                width: row34CellWidth,
                                height: row34CellHeight,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode
                            )
                        } else {
                            Color.clear.frame(width: row34CellWidth, height: row34CellHeight)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sheet Types for FeaturedPostCellSimple
enum FeaturedPostSheet: Identifiable {
    case report
    case comments

    var id: Int {
        hashValue
    }
}

// MARK: - Simplified Featured Post Cell (for discovery view without user parameter)
struct FeaturedPostCellSimple: View {
    let post: Post
    let width: CGFloat
    let height: CGFloat
    @Binding var showingLoginPrompt: Bool
    var isScreenshotMode: Bool = false
    var showUserInfo: Bool = true
    var showDate: Bool = true // 投稿日時を表示するか（フィードでは非表示にする）
    let safeAreaTop: CGFloat
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var musicKit = MusicKitManager.shared
    @StateObject private var playbackState = PlaybackStateManager.shared
    @State private var showingActionSheet = false
    @State private var showingBlockConfirmation = false
    @State private var activeSheet: FeaturedPostSheet?
    @State private var showingUserProfile = false
    @State private var likeAnimationScale: CGFloat = 1.0
    @State private var menuAnimationScale: CGFloat = 1.0
    @ObservedObject private var likeState = LikeStateManager.shared
    @ObservedObject private var commentState = CommentStateManager.shared
    @State private var postUser: User? = nil  // Post owner user info

    var isPlaying: Bool {
        guard let postId = post.id else { return false }
        return playbackState.isPlaying(postId)
    }

    var isLiked: Bool {
        guard let postId = post.id else { return false }
        return likeState.isLiked(postId)
    }

    var likeCount: Int {
        guard let postId = post.id else { return 0 }
        return likeState.getLikeCount(postId)
    }

    var commentCount: Int {
        guard let postId = post.id else { return 0 }
        return commentState.getCommentCount(postId)
    }

    // Left column: content type badge, title, description, user info, comment
    @ViewBuilder
    private var trackInfoColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Content type badge
            if let type = post.contentType {
                if type == ContentType.youtube.rawValue {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                        Text("YouTube")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(6)
                } else if type == ContentType.website.rawValue {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .foregroundColor(.blue)
                            .font(.system(size: 14))
                        Text("Website")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(6)
                }
            }

            HStack(spacing: 6) {
                Text(post.contentTitle ?? post.trackName ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Waveform animation when playing (only for music)
                if isPlaying && (post.contentType == nil || post.contentType == ContentType.music.rawValue) {
                    MiniWaveformView()
                        .frame(width: 30, height: 20)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)

            HStack(spacing: 6) {
                Text(post.contentDescription ?? post.artistName ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)

                // アーティスト名で検索するボタン（artistName がある場合のみ）
                if let artist = post.artistName, !artist.isEmpty {
                    NavigationLink(destination: ArtistPostsView(artistName: artist)) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(4)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)

            // User info + post date (showUserInfoがtrueの場合のみ)
            if showUserInfo {
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

                        if showDate {
                            Text("・")
                                .foregroundColor(.white.opacity(0.5))

                            Text(formatPostDate(post.createdAt))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                }
            }

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
        }
    }

    var body: some View {
        ZStack {
            // Background image (artwork for music, thumbnail for YouTube, image for website)
            let backgroundImageUrl: String? = {
                let type = post.contentType ?? ContentType.music.rawValue
                if type == ContentType.youtube.rawValue {
                    return post.youtubeThumbnailUrl
                } else if type == ContentType.website.rawValue {
                    return post.websiteImageUrl
                } else {
                    return post.artworkUrl
                }
            }()

            ArtworkImageView(
                artworkUrl: backgroundImageUrl,
                placeholder: {
                    let type = post.contentType ?? ContentType.music.rawValue
                    if type == ContentType.youtube.rawValue {
                        return "play.rectangle.fill"
                    } else if type == ContentType.website.rawValue {
                        return "globe"
                    } else {
                        return "music.note"
                    }
                }(),
                width: width,
                height: height
            )
            .frame(width: width, height: height)
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
                // Top: Menu button (normal mode only)
                if !isScreenshotMode {
                    HStack {
                        Spacer()

                        // Menu button with shadow and animation
                        Button(action: {
                            if !authManager.isAuthenticated {
                                showingLoginPrompt = true
                                return
                            }
                            // タップアニメーション
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                menuAnimationScale = 0.8
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    menuAnimationScale = 1.0
                                }
                            }
                            showingActionSheet = true
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
                    .padding(.top, 12 + safeAreaTop)
                }

                Spacer()

                // Bottom: Track info (left) and likes/comments (right) (hidden in screenshot mode)
                if !isScreenshotMode {
                    HStack(alignment: .bottom, spacing: 12) {
                        // Left: Track info with background shadow
                        trackInfoColumn

                        Spacer()

                        // Right: Likes and comments count with background shadow
                        VStack(alignment: .center, spacing: 10) {
                            // Like button with animation
                            Button(action: {
                                if !authManager.isAuthenticated {
                                    showingLoginPrompt = true
                                    return
                                }
                                // ハートのポップアニメーション
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

                            // Comment button - navigate to comments
                            Button(action: {
                                if !authManager.isAuthenticated {
                                    showingLoginPrompt = true
                                    return
                                }
                                activeSheet = .comments
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
        }
        .frame(width: width, height: height)
        .cornerRadius(4)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    Color.white.opacity(0.7),
                    lineWidth: isPlaying ? 3 : 0
                )
        )
        .onTapGesture {
            if !isScreenshotMode {
                Task {
                    await playMusic()
                }
            }
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            if let appleMusicUrl = post.appleMusicUrl, let url = URL(string: appleMusicUrl) {
                Button("Apple Musicで開く") {
                    UIApplication.shared.open(url)
                }
            }

            if let currentUserId = Auth.auth().currentUser?.uid, currentUserId == post.userId {
                Button("削除", role: .destructive) {
                    Task {
                        await deletePost()
                    }
                }
            } else {
                Button("報告") {
                    activeSheet = .report
                }
                Button("ブロック", role: .destructive) {
                    showingBlockConfirmation = true
                }
            }

            Button("キャンセル", role: .cancel) {}
        }
        .tint(.primary)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .fullScreenCover(isPresented: $showingUserProfile) {
            UserProfileView(userId: post.userId)
        }
        .alert("ブロック確認", isPresented: $showingBlockConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("\(postUser?.displayName ?? "このユーザー")さんをブロックしますか？")
        }
        .onAppear {
            // Update like and comment state from server data
            if let postId = post.id {
                likeState.updateFromServer(
                    postId: postId,
                    isLiked: post.isLiked ?? false,
                    count: post.likeCount ?? 0
                )
                commentState.initialize(postId: postId, count: post.commentCount ?? 0)
            }
        }
        .task(id: post.id ?? "") {
            // Load user info for the displayed post
            if postUser == nil {
                postUser = try? await FirestoreUserManager.shared.getUser(userId: post.userId)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: FeaturedPostSheet) -> some View {
        switch sheet {
        case .report:
            ReportPostView(post: post)
        case .comments:
            NavigationStack {
                CommentsView(post: post)
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
            print("Failed to toggle like: \(error)")
        }
    }

    private func playMusic() async {
        guard let postId = post.id else { return }

        if isPlaying {
            musicKit.stopPreview()
            playbackState.stopPlayback()
            return
        }

        if let previewUrl = post.previewUrl {
            do {
                try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                playbackState.startPlayback(for: postId, userId: post.userId, post: post, user: nil)
            } catch {
                print("Failed to play preview: \(error)")
            }
        }
    }

    private func deletePost() async {
        guard let postId = post.id else { return }

        do {
            try await FirestorePostManager.shared.deletePost(postId: postId)
            // 通知を発行して即座に反映
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.postDeleted,
                object: nil,
                userInfo: ["postId": postId]
            )
        } catch {
            print("Failed to delete post: \(error)")
        }
    }

    private func blockUser() async {
        do {
            try await FirestoreBlockManager.shared.blockUser(userId: post.userId)
            print("🚫 Block succeeded for userId: \(post.userId), posting notification...")
            // 通知を発行して即座に反映
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Foundation.Notification.Name.userBlocked,
                    object: nil,
                    userInfo: ["userId": post.userId]
                )
            }
            print("🚫 Block notification posted for userId: \(post.userId)")
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

// MARK: - Mini Waveform View
struct MiniWaveformView: View {
    @State private var animationValues: [CGFloat] = Array(repeating: 0.3, count: 3)
    let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        AppTheme.verticalGradient
                    )
                    .frame(width: 3, height: animationValues[index] * 20)
                    .animation(.easeInOut(duration: 0.3), value: animationValues[index])
            }
        }
        .onReceive(timer) { _ in
            for index in 0..<3 {
                animationValues[index] = CGFloat.random(in: 0.3...1.0)
            }
        }
    }
}

// MARK: - Small Post Cell
struct SmallPostCell: View {
    let post: Post
    let width: CGFloat
    let height: CGFloat
    @Binding var showingLoginPrompt: Bool
    var isScreenshotMode: Bool = false
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var musicKit = MusicKitManager.shared
    @StateObject private var playbackState = PlaybackStateManager.shared

    // Long press state
    @State private var showingActionSheet = false
    @State private var showingBlockConfirmation = false
    @State private var showingReportSheet = false
    @State private var showingUserProfile = false
    @State private var cellScale: CGFloat = 1.0
    @State private var postUser: User? = nil  // Post owner user info

    var isPlaying: Bool {
        guard let postId = post.id else { return false }
        return playbackState.isPlaying(postId)
    }

    var isOwnPost: Bool {
        authManager.currentUser?.id == post.userId
    }

    var body: some View {
        let backgroundImageUrl: String? = {
            let type = post.contentType ?? ContentType.music.rawValue
            if type == ContentType.youtube.rawValue {
                return post.youtubeThumbnailUrl
            } else if type == ContentType.website.rawValue {
                return post.websiteImageUrl
            } else {
                return post.artworkUrl
            }
        }()

        ZStack {
            ArtworkImageView(
                artworkUrl: backgroundImageUrl,
                placeholder: {
                    let type = post.contentType ?? ContentType.music.rawValue
                    if type == ContentType.youtube.rawValue {
                        return "play.rectangle.fill"
                    } else if type == ContentType.website.rawValue {
                        return "globe"
                    } else {
                        return "music.note"
                    }
                }(),
                width: width,
                height: height
            )
            .frame(width: width, height: height)
            .clipped()
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Color.white.opacity(0.7),
                        lineWidth: isPlaying ? 3 : 0
                    )
            )

            // Content type badge (top-left corner)
            if let type = post.contentType {
                if type == ContentType.youtube.rawValue || type == ContentType.website.rawValue {
                    VStack {
                        HStack {
                            Image(systemName: type == ContentType.youtube.rawValue ? "play.circle.fill" : "safari")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(type == ContentType.youtube.rawValue ? Color.red.opacity(0.8) : Color.blue.opacity(0.8))
                                .cornerRadius(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }

            // Loading indicator or waveform animation when playing (centered)
            if musicKit.isLoadingPreview && isPlaying {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else if isPlaying {
                MiniWaveformView()
                    .frame(width: 30, height: 20)
            }
        }
        .scaleEffect(cellScale)
        .onTapGesture {
            // Disable music playback in screenshot mode
            if !isScreenshotMode {
                Task {
                    await playMusic()
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.3, pressing: { isPressing in
            // Scale animation on press
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                cellScale = isPressing ? 1.15 : 1.0
            }
        }) {
            // Trigger haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            // 未ログインの場合はログインを促す
            if !authManager.isAuthenticated {
                showingLoginPrompt = true
            } else {
                showingActionSheet = true
            }
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            if let appleMusicUrl = post.appleMusicUrl, let url = URL(string: appleMusicUrl) {
                Button("Apple Musicで開く") {
                    UIApplication.shared.open(url)
                }
            }

            Button("プロフィールを見る") {
                showingUserProfile = true
            }

            if isOwnPost {
                Button("削除", role: .destructive) {
                    Task {
                        await deletePost()
                    }
                }
            } else {
                Button("報告") {
                    showingReportSheet = true
                }
                Button("ブロック", role: .destructive) {
                    showingBlockConfirmation = true
                }
            }

            Button("キャンセル", role: .cancel) {}
        }
        .tint(.primary)
        .fullScreenCover(isPresented: $showingUserProfile) {
            UserProfileView(userId: post.userId)
        }
        .sheet(isPresented: $showingReportSheet) {
            ReportPostView(post: post)
        }
        .alert("ブロック確認", isPresented: $showingBlockConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("\(postUser?.displayName ?? "このユーザー")さんをブロックしますか？")
        }
        .task(id: post.id) {
            // Load user info for the displayed post
            if postUser == nil {
                postUser = try? await FirestoreUserManager.shared.getUser(userId: post.userId)
            }
        }
    }

    private func playMusic() async {
        guard let postId = post.id else { return }

        // Toggle play/pause if already playing
        if isPlaying {
            musicKit.stopPreview()
            playbackState.stopPlayback()
            print("⏸️ Stopped preview for: \(post.trackName)")
            return
        }

        // Play music preview if available
        if let previewUrl = post.previewUrl {
            do {
                try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                playbackState.startPlayback(for: postId, userId: post.userId, post: post, user: nil)
                print("🎵 Playing preview for: \(post.trackName ?? "unknown")")
            } catch {
                print("❌ Failed to play preview: \(error)")
            }
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
        } catch {
            print("Failed to delete post: \(error)")
        }
    }

    private func blockUser() async {
        do {
            try await FirestoreBlockManager.shared.blockUser(userId: post.userId)
            print("🚫 Block succeeded for userId: \(post.userId), posting notification...")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Foundation.Notification.Name.userBlocked,
                    object: nil,
                    userInfo: ["userId": post.userId]
                )
            }
            print("🚫 Block notification posted for userId: \(post.userId)")
        } catch {
            print("❌ Failed to block user: \(error)")
        }
    }
}

// MARK: - User Info Cell (for screenshot mode grid)
struct UserInfoCell: View {
    let width: CGFloat
    let height: CGFloat
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        let _ = print("🎨 [UserInfoCell] Creating cell - width: \(width), height: \(height), username: \(authManager.currentUser?.username ?? "nil")")

        // デバッグ用：超シンプルで目立つバージョン
        ZStack {
            // 真っ赤な背景（絶対に見える）
            Color.red

            // 大きな白いテキスト
            VStack(spacing: 4) {
                Text("USER")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                if let username = authManager.currentUser?.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("@???")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: width, height: height)
        .border(Color.yellow, width: 5) // 黄色い枠線
    }
}

// MARK: - Artwork Image View with Retry

/// Apple MusicのアートワークURLを適切に処理するカスタムAsyncImage
/// エラー時に異なるサイズでリトライし、ネットワークの一時的な問題にも対応
struct ArtworkImageView: View {
    let artworkUrl: String?
    let placeholder: String
    let width: CGFloat?
    let height: CGFloat?

    @State private var currentUrl: URL?
    @State private var hasError = false
    @State private var retryCount = 0
    @State private var loadId = UUID() // URLを強制的に再ロードするためのID

    private let maxRetries = 2  // Optimized: Reduced from 4 to 2
    private let imageSizes = [600, 1000] // Optimized: Reduced from 5 to 2 most common sizes

    init(artworkUrl: String?, placeholder: String = "music.note", width: CGFloat? = nil, height: CGFloat? = nil) {
        self.artworkUrl = artworkUrl
        self.placeholder = placeholder
        self.width = width
        self.height = height
    }

    var body: some View {
        Group {
            if let url = currentUrl, !hasError {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(let error):
                        // エラー時は少し待ってからリトライ
                        Color.clear
                            .onAppear {
                                // Optimized: Reduced delay from 0.3s to 0.1s
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    retryWithDifferentSize()
                                }
                            }
                    case .empty:
                        // ローディング中
                        Color.gray.opacity(0.3)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                    @unknown default:
                        placeholderView
                    }
                }
                .id(loadId) // IDを使用して強制的に再ロード
            } else {
                placeholderView
            }
        }
        .onAppear {
            setupInitialUrl()
            // ビューが再表示されたとき（スクショモード終了後など）に
            // AsyncImageがローディング状態のまま固まらないよう、強制的に作り直す
            if currentUrl != nil, !hasError {
                loadId = UUID()
            }
        }
        .onChange(of: artworkUrl) { newUrl in
            // artworkUrlが実際に変わった場合のみ処理
            guard newUrl != currentUrl?.absoluteString else {
                return
            }

            // リセットして再初期化
            retryCount = 0
            hasError = false
            setupInitialUrl()  // currentUrlを更新（loadId更新は不要）
        }
    }

    private var placeholderView: some View {
        Color.gray.opacity(0.3)
            .overlay(
                Image(systemName: placeholder)
                    .font(.system(size: min(width ?? 60, height ?? 60) * 0.4))
                    .foregroundColor(.white.opacity(0.3))
            )
    }

    private func setupInitialUrl() {
        guard let urlString = artworkUrl, !urlString.isEmpty else {
            hasError = true
            return
        }

        // 元のURLをそのまま使用（最初のリトライ）
        currentUrl = URL(string: urlString)
    }

    private func retryWithDifferentSize() {
        retryCount += 1

        guard retryCount <= maxRetries else {
            // リトライ回数上限に達したらプレースホルダーを表示
            hasError = true
            currentUrl = nil
            return
        }

        guard let urlString = artworkUrl else {
            hasError = true
            return
        }

        if retryCount == 1 {
            // 最初のリトライ: 同じURLでもう一度試す（ネットワークの一時的な問題の可能性）
            loadId = UUID()
        } else if retryCount - 2 < imageSizes.count {
            // 2回目以降: 異なるサイズで試す
            let sizeIndex = retryCount - 2
            let processedUrl = processArtworkUrl(urlString, size: imageSizes[sizeIndex])
            currentUrl = URL(string: processedUrl)
            loadId = UUID()
        } else {
            // すべてのサイズを試したらエラー
            hasError = true
            currentUrl = nil
        }
    }

    private func processArtworkUrl(_ urlString: String, size: Int) -> String {
        var processed = urlString

        // Apple MusicのアートワークURLのプレースホルダーを置き換える
        // 例: https://is1-ssl.mzstatic.com/image/thumb/.../300x300bb.jpg
        //     https://example.com/artwork/{w}x{h}bb.jpg

        // {w}x{h}のパターンを実際のサイズに置き換え
        processed = processed.replacingOccurrences(of: "{w}x{h}", with: "\(size)x\(size)")
        processed = processed.replacingOccurrences(of: "{w}", with: "\(size)")
        processed = processed.replacingOccurrences(of: "{h}", with: "\(size)")

        // サイズのパターン（例: 300x300, 600x600）を見つけて置き換え
        // Apple MusicのURLには通常 "600x600bb.jpg" のような形式が含まれる
        let pattern = "(\\d+)x(\\d+)bb"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(processed.startIndex..., in: processed)
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: range,
                withTemplate: "\(size)x\(size)bb"
            )
        }

        return processed
    }
}
