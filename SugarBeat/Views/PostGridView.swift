import SwiftUI

/// 再利用可能な投稿グリッドレイアウト
/// - 最初の投稿を大きなセルで表示
/// - 残りの投稿をグリッドレイアウトで表示
struct PostGridView: View {
    let posts: [Post]
    @Binding var showingLoginPrompt: Bool
    var isScreenshotMode: Bool = false
    var showUserInfo: Bool = true // 大きいセルにユーザー情報を表示するか
    var isLoading: Bool = false // リフレッシュ中のローディング表示
    var onRefresh: (() async -> Void)? = nil // リフレッシュコールバック

    @StateObject private var screenshotMode = ScreenshotModeManager.shared
    @ObservedObject private var playbackState = PlaybackStateManager.shared

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

            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 一番上のグリッド
                        if let post = displayPost {
                            FeaturedPostCellSimple(
                                post: post,
                                width: screenWidth,
                                height: featuredHeight,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode,
                                showUserInfo: showUserInfo,
                                safeAreaTop: 0
                            )
                            .frame(width: screenWidth, height: featuredHeight)
                        }

                        // 残りのグリッド
                        if posts.count > 1 {
                            gridLayout(posts: Array(posts.dropFirst()), screenWidth: screenWidth, spacing: spacing)
                                .padding(.top, spacing)
                        }
                    }
                }
                .refreshable {
                    if let refresh = onRefresh {
                        await refresh()
                    }
                }
                .tint(AppTheme.tintColor)
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

                // リフレッシュ中のローディングオーバーレイ
                if isLoading {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
        }
        .toolbar(screenshotMode.isScreenshotMode ? .hidden : .visible, for: .tabBar)
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

        VStack(spacing: spacing) {
            // 投稿数が少ない場合は単純な4列グリッドを使用
            if posts.count < 9 {
                // シンプルな4列グリッド（左詰め）
                let rowCount = (posts.count + 3) / 4
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

                    if posts.count > 3 {
                        SmallPostCell(
                            post: posts[3],
                            width: mergedCellWidth6,
                            height: mergedCellHeight6,
                            showingLoginPrompt: $showingLoginPrompt,
                            isScreenshotMode: screenshotMode.isScreenshotMode
                        )
                    }

                    VStack(spacing: spacing) {
                        if posts.count > 4 {
                            SmallPostCell(
                                post: posts[4],
                                width: columns6Width,
                                height: columns6Width,
                                showingLoginPrompt: $showingLoginPrompt,
                                isScreenshotMode: screenshotMode.isScreenshotMode
                            )
                        } else {
                            Color.clear.frame(width: columns6Width, height: columns6Width)
                        }
                        if posts.count > 8 {
                            SmallPostCell(
                                post: posts[8],
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

    var isPlaying: Bool {
        playbackState.isPlaying(post.id)
    }

    var isLiked: Bool {
        likeState.isLiked(post.id)
    }

    var likeCount: Int {
        likeState.getLikeCount(post.id)
    }

    var commentCount: Int {
        post.commentCount ?? 0
    }

    var body: some View {
        ZStack {
            // Background artwork
            AsyncImage(url: URL(string: post.artworkUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: width, height: height)
            .clipped()

            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                // Top: Menu button only (hidden in screenshot mode)
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(post.trackName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                // Waveform animation when playing
                                if isPlaying {
                                    MiniWaveformView()
                                        .frame(width: 30, height: 20)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)

                            Text(post.artistName)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
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
                                        AsyncImage(url: URL(string: APIClient.shared.getFullImageURL(post.user.profileImageUrl) ?? "")) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        .frame(width: 20, height: 20)
                                        .clipShape(Circle())

                                        Text(post.user.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))

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

                        Spacer()

                        // Right: Likes and comments count with background shadow
                        VStack(alignment: .center, spacing: 10) {
                            // Like button with animation
                            Button(action: {
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
                    LinearGradient(
                        gradient: Gradient(colors: [
                            AppTheme.gradientStartColor.opacity(0.9),
                            AppTheme.gradientEndColor.opacity(0.7)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
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

            if let currentUserId = authManager.currentUser?.userId, currentUserId == post.user.id {
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
        .sheet(isPresented: $showingUserProfile) {
            UserProfileView(userId: post.user.id)
        }
        .alert("ブロック確認", isPresented: $showingBlockConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("\(post.user.displayName)さんをブロックしますか？")
        }
        .onAppear {
            // Update like state from server data
            likeState.updateFromServer(
                postId: post.id,
                isLiked: post.isLiked ?? false,
                count: post.likeCount ?? 0
            )
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

        let wasLiked = isLiked
        likeState.toggleLike(postId: post.id)

        do {
            if wasLiked {
                try await APIClient.shared.unlikePost(postId: post.id)
            } else {
                try await APIClient.shared.likePost(postId: post.id)
            }
        } catch {
            likeState.toggleLike(postId: post.id)
            print("Failed to toggle like: \(error)")
        }
    }

    private func playMusic() async {
        if isPlaying {
            musicKit.stopPreview()
            playbackState.stopPlayback()
            return
        }

        if let previewUrl = post.previewUrl {
            do {
                try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime)
                playbackState.startPlayback(for: post.id, userId: post.user.id, post: post, user: post.user)
            } catch {
                print("Failed to play preview: \(error)")
            }
        }
    }

    private func deletePost() async {
        do {
            try await APIClient.shared.deletePost(postId: post.id)
            // 通知を発行して即座に反映
            NotificationCenter.default.post(
                name: Foundation.Notification.Name.postDeleted,
                object: nil,
                userInfo: ["postId": post.id]
            )
        } catch {
            print("Failed to delete post: \(error)")
        }
    }

    private func blockUser() async {
        do {
            try await APIClient.shared.blockUser(userId: post.user.id)
            print("🚫 Block succeeded for userId: \(post.user.id), posting notification...")
            // 通知を発行して即座に反映
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Foundation.Notification.Name.userBlocked,
                    object: nil,
                    userInfo: ["userId": post.user.id]
                )
            }
            print("🚫 Block notification posted for userId: \(post.user.id)")
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
