import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @Binding var refreshTrigger: Bool
    @State private var showingMenu = false
    @State private var showingUserSearch = false
    @State private var showingCreatePost = false
    @State private var showingProfile = false
    @State private var postCreated = false

    var body: some View {
        ZStack {
            // Background color
            Color.black.ignoresSafeArea()

            // Content
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            } else if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text("エラー")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            } else if viewModel.allUserPosts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.4))
                    Text("投稿がありません")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                    Text("投稿を作成するか、ユーザーをフォローして音楽を共有しましょう")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            } else {
                // All user posts with horizontal and vertical navigation
                AllUserPostsView(
                    allUserPosts: viewModel.allUserPosts,
                    onRefresh: {
                        Task {
                            await viewModel.refreshFeed()
                        }
                    }
                )
            }

            // Dark overlay when menu is shown
            if showingMenu {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showingMenu = false
                        }
                    }
                    .transition(.opacity)
            }

            // Floating action button (always visible, bottom left)
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        // Expanded menu buttons (positioned absolutely above main button)
                        if showingMenu {
                            VStack(alignment: .leading, spacing: 16) {
                                // Profile button
                                FloatingMenuButton(icon: "person", label: "プロフィール") {
                                    showingProfile = true
                                    showingMenu = false
                                }

                                // Post button
                                FloatingMenuButton(icon: "plus", label: "投稿") {
                                    showingCreatePost = true
                                    showingMenu = false
                                }

                                // Search button
                                FloatingMenuButton(icon: "magnifyingglass", label: "検索") {
                                    showingUserSearch = true
                                    showingMenu = false
                                }
                            }
                            .offset(y: -72)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Main button (fixed position)
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingMenu.toggle()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                    .blur(radius: 10)

                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 56, height: 56)

                                Image(systemName: showingMenu ? "xmark" : "ellipsis")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .rotationEffect(.degrees(showingMenu ? 0 : 90))
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 100)

                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .refreshable {
            await viewModel.refreshFeed()
        }
        .task {
            await viewModel.loadFeed()
        }
        .onChange(of: refreshTrigger) { _ in
            Task {
                await viewModel.refreshFeed()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Clear like and comment state and refresh feed when app returns to foreground
            LikeStateManager.shared.clear()
            CommentStateManager.shared.clear()
            Task {
                await viewModel.refreshFeed()
            }
        }
        .sheet(isPresented: $showingUserSearch) {
            UserSearchView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showingCreatePost, onDismiss: {
            if postCreated {
                refreshTrigger.toggle()
                postCreated = false
            }
        }) {
            CreatePostView(postCreated: $postCreated)
        }
    }
}

struct FloatingMenuButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .blur(radius: 8)

                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// Horizontal view for navigating between all users' posts
struct AllUserPostsView: View {
    let allUserPosts: [UserPosts]
    let onRefresh: () -> Void
    @State private var currentUserIndex = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            ZStack {
                Color.black
                    .ignoresSafeArea()

                // Main content with horizontal slide (same as vertical)
                if !allUserPosts.isEmpty && currentUserIndex < allUserPosts.count {
                    ZStack {
                        let previousIndex = (currentUserIndex - 1 + allUserPosts.count) % allUserPosts.count
                        let nextIndex = (currentUserIndex + 1) % allUserPosts.count

                        // Previous user - always rendered (on the left)
                        if previousIndex < allUserPosts.count {
                            UserPostsScrollView(userPosts: allUserPosts[previousIndex], isCurrent: false, onRefresh: onRefresh)
                                .frame(width: screenWidth, height: screenHeight)
                                .offset(x: -screenWidth + horizontalDragOffset)
                                .zIndex(horizontalDragOffset > 0 ? 1 : 0)
                                .id("\(allUserPosts[previousIndex].id)-\(previousIndex)")
                        }

                        // Current user - always rendered
                        UserPostsScrollView(userPosts: allUserPosts[currentUserIndex], isCurrent: true, onRefresh: onRefresh)
                            .frame(width: screenWidth, height: screenHeight)
                            .offset(x: horizontalDragOffset)
                            .zIndex(2)
                            .id("\(allUserPosts[currentUserIndex].id)-\(currentUserIndex)")

                        // Next user - always rendered (on the right)
                        if nextIndex < allUserPosts.count {
                            UserPostsScrollView(userPosts: allUserPosts[nextIndex], isCurrent: false, onRefresh: onRefresh)
                                .frame(width: screenWidth, height: screenHeight)
                                .offset(x: screenWidth + horizontalDragOffset)
                                .zIndex(horizontalDragOffset < 0 ? 1 : 0)
                                .id("\(allUserPosts[nextIndex].id)-\(nextIndex)")
                        }
                    }
                    .clipped()
                    .frame(width: screenWidth, height: screenHeight)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                // Ignore gestures while animating
                                guard !isAnimating else { return }

                                // Determine if this is a horizontal or vertical swipe
                                let horizontalAmount = abs(value.translation.width)
                                let verticalAmount = abs(value.translation.height)

                                // Only capture horizontal swipes for user switching
                                // Vertical swipes will be handled by UserPostsScrollView
                                if horizontalAmount > verticalAmount {
                                    horizontalDragOffset = value.translation.width
                                }
                            }
                            .onEnded { value in
                                // Ignore gestures while animating
                                guard !isAnimating else { return }

                                let horizontalAmount = abs(value.translation.width)
                                let verticalAmount = abs(value.translation.height)

                                // Only handle horizontal swipes here
                                if horizontalAmount > verticalAmount {
                                    let threshold = screenWidth * 0.3
                                    let velocity = value.predictedEndTranslation.width - value.translation.width

                                    if value.translation.width < -threshold || velocity < -500 {
                                        // Swipe left - next user
                                        isAnimating = true

                                        // Animate to show next user
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            horizontalDragOffset = -screenWidth
                                        }

                                        // Update state immediately to prepare new views
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                            var transaction = Transaction()
                                            transaction.disablesAnimations = true
                                            withTransaction(transaction) {
                                                currentUserIndex = (currentUserIndex + 1) % allUserPosts.count
                                                horizontalDragOffset = 0
                                                isAnimating = false
                                            }
                                        }
                                    } else if value.translation.width > threshold || velocity > 500 {
                                        // Swipe right - previous user
                                        isAnimating = true

                                        // Animate to show previous user
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            horizontalDragOffset = screenWidth
                                        }

                                        // Update state immediately to prepare new views
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                            var transaction = Transaction()
                                            transaction.disablesAnimations = true
                                            withTransaction(transaction) {
                                                currentUserIndex = (currentUserIndex - 1 + allUserPosts.count) % allUserPosts.count
                                                horizontalDragOffset = 0
                                                isAnimating = false
                                            }
                                        }
                                    } else {
                                        // Return to center
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            horizontalDragOffset = 0
                                        }
                                    }
                                }
                            }
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reset animation states when app returns to foreground
            horizontalDragOffset = 0
            isAnimating = false
        }
    }
}

// Vertical scroll view for a user's posts with simple swipe
struct UserPostsScrollView: View {
    let userPosts: UserPosts
    let isCurrent: Bool
    let onRefresh: () -> Void
    @State private var currentPostIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let screenWidth = geometry.size.width

            if userPosts.posts.isEmpty {
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 20) {
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("投稿がありません")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    )
            } else {
                // Always render 3 posts: previous, current, next
                let previousIndex = (currentPostIndex - 1 + userPosts.posts.count) % userPosts.posts.count
                let nextIndex = (currentPostIndex + 1) % userPosts.posts.count

                ZStack {
                    Color.black.ignoresSafeArea()

                    // Previous post - always rendered
                    PostCardView(post: userPosts.posts[previousIndex], isCurrent: false, onDelete: onRefresh)
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: -screenHeight + dragOffset)
                        .zIndex(dragOffset > 0 ? 1 : 0)
                        .id(userPosts.posts[previousIndex].id)

                    // Current post - always rendered
                    PostCardView(post: userPosts.posts[currentPostIndex], isCurrent: true, onDelete: onRefresh)
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: dragOffset)
                        .zIndex(2)
                        .id(userPosts.posts[currentPostIndex].id)

                    // Next post - always rendered
                    PostCardView(post: userPosts.posts[nextIndex], isCurrent: false, onDelete: onRefresh)
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: screenHeight + dragOffset)
                        .zIndex(dragOffset < 0 ? 1 : 0)
                        .id(userPosts.posts[nextIndex].id)
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only handle vertical drags
                            let horizontalAmount = abs(value.translation.width)
                            let verticalAmount = abs(value.translation.height)

                            if verticalAmount > horizontalAmount {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            // Only handle vertical drags
                            let horizontalAmount = abs(value.translation.width)
                            let verticalAmount = abs(value.translation.height)

                            if horizontalAmount > verticalAmount {
                                // Horizontal drag - reset and let parent handle
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                                return
                            }

                            let threshold = screenHeight * 0.3
                            let velocity = value.predictedEndTranslation.height - value.translation.height

                            if value.translation.height < -threshold || velocity < -500 {
                                // Swipe up - next post (infinite loop)
                                isAnimating = true

                                // Animate to show next post
                                withAnimation(.easeOut(duration: 0.25)) {
                                    dragOffset = -screenHeight
                                }

                                // Update state immediately to prepare new views
                                DispatchQueue.main.async {
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        currentPostIndex = (currentPostIndex + 1) % userPosts.posts.count
                                        dragOffset = 0
                                        isAnimating = false
                                    }
                                }
                            } else if value.translation.height > threshold || velocity > 500 {
                                // Swipe down - previous post (infinite loop)
                                isAnimating = true

                                // Animate to show previous post
                                withAnimation(.easeOut(duration: 0.25)) {
                                    dragOffset = screenHeight
                                }

                                // Update state immediately to prepare new views
                                DispatchQueue.main.async {
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        currentPostIndex = (currentPostIndex - 1 + userPosts.posts.count) % userPosts.posts.count
                                        dragOffset = 0
                                        isAnimating = false
                                    }
                                }
                            } else {
                                // Return to original position
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reset animation states when app returns to foreground
            dragOffset = 0
            isAnimating = false
        }
    }
}

struct PostCardView: View {
    let post: Post
    let isCurrent: Bool
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var playbackStateManager = PlaybackStateManager.shared
    @ObservedObject private var likeStateManager = LikeStateManager.shared
    @ObservedObject private var commentStateManager = CommentStateManager.shared
    private let musicPlayer = MusicKitManager.shared
    @State private var showingDeleteConfirmation = false
    @State private var showingComments = false
    @State private var showingReportCommentSheet = false
    @State private var commentToReport: Comment?
    @State private var showingReportPostSheet = false
    @State private var showingPostActions = false

    init(post: Post, isCurrent: Bool, onDelete: (() -> Void)? = nil) {
        self.post = post
        self.isCurrent = isCurrent
        self.onDelete = onDelete

        // Initialize like state in the manager
        LikeStateManager.shared.initialize(
            postId: post.id,
            isLiked: post.isLiked ?? false,
            count: post.likeCount ?? 0
        )

        // Initialize comment state in the manager
        CommentStateManager.shared.initialize(
            postId: post.id,
            count: post.commentCount ?? 0
        )
    }

    private var isPlaying: Bool {
        playbackStateManager.currentlyPlayingPostId == post.id
    }

    private var isLiked: Bool {
        likeStateManager.isLiked(post.id)
    }

    private var likeCount: Int {
        likeStateManager.getLikeCount(post.id)
    }

    private var commentCount: Int {
        commentStateManager.getCommentCount(post.id)
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let albumLeftPadding = (screenWidth - 280) / 2

            ZStack(alignment: .bottom) {
                // Black background to prevent white background showing
                Color.black
                    .frame(width: screenWidth, height: screenHeight)
                    .zIndex(0)

                // Background artwork with blur
                AsyncImage(url: URL(string: post.artworkUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: screenWidth, height: screenHeight)
                        .blur(radius: 50)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.6),
                                    Color.blue.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: screenWidth, height: screenHeight)
                }
                .allowsHitTesting(false)
                .zIndex(1)

                // Dark overlay
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.3),
                                Color.black.opacity(0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: screenWidth, height: screenHeight)
                    .allowsHitTesting(false)
                    .zIndex(2)

                // Content
                VStack(spacing: 0) {
                    Spacer().frame(height: 80)

                // Track info (top, with reduced spacing)
                VStack(spacing: 4) {
                    Text(post.trackName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                        .lineLimit(2)

                    Text(post.artistName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)

                    if let albumName = post.albumName {
                        Text(albumName)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                    // Album artwork with play button overlay (moved up)
                    ZStack {
                        AsyncImage(url: URL(string: post.artworkUrl ?? "")) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .failure:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            @unknown default:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                        }
                        .frame(width: 280, height: 280)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)

                        // Three-dot menu button (top-right) - for all posts
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    showingPostActions = true
                                }) {
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                                .rotationEffect(.degrees(90))
                                        )
                                }
                                .padding(8)
                            }
                            Spacer()
                        }
                        .frame(width: 280, height: 280)

                        // Play button with waveform overlay (bottom-left)
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Button(action: {
                                    Task {
                                        await togglePlayback()
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.95),
                                                        Color.white.opacity(0.85)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 60, height: 60)
                                            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)

                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.black)
                                            .offset(x: isPlaying ? 0 : 2)
                                    }
                                }

                                if isPlaying {
                                    WaveformView()
                                        .frame(width: 80, height: 50)
                                        .transition(.scale.combined(with: .opacity))
                                }

                                Spacer()
                            }
                            .padding(16)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPlaying)
                        }
                        .frame(width: 280, height: 280)

                        // Like and Comment buttons (bottom-right)
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    // Like button
                                    Button(action: {
                                        Task {
                                            await toggleLike()
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                                .font(.system(size: 20))
                                                .foregroundColor(isLiked ? .red : .white)
                                            Text("\(likeCount)")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(20)
                                    }

                                    // Comment button
                                    Button(action: {
                                        showingComments = true
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "bubble.right")
                                                .font(.system(size: 20))
                                            Text("\(commentCount)")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(20)
                                    }
                                }
                                .padding(16)
                            }
                        }
                        .frame(width: 280, height: 280)
                    }
                    .padding(.bottom, 20)

                    // User profile (below artwork)
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.user.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)

                            Text("@\(post.user.username)")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }

                        Spacer()
                    }
                    .padding(.leading, albumLeftPadding)
                    .padding(.trailing, 32)
                    .padding(.bottom, 16)

                    // Comment section
                    if let comment = post.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, albumLeftPadding)
                            .padding(.trailing, 32)
                            .padding(.bottom, 16)
                    }

                Spacer()
            }
            .zIndex(1000)
            }
        }
        .onChange(of: isCurrent) { newValue in
            if !newValue && isPlaying {
                musicPlayer.stopPreview()
                playbackStateManager.stopPlayback()
            }
        }
        .onDisappear {
            // Stop playback when post disappears
            if isPlaying {
                musicPlayer.stopPreview()
                playbackStateManager.stopPlayback()
            }
        }
        .sheet(isPresented: $showingReportCommentSheet) {
            if let comment = commentToReport {
                ReportCommentView(comment: comment)
            }
        }
        .sheet(isPresented: $showingReportPostSheet) {
            ReportPostView(post: post)
        }
        .confirmationDialog("", isPresented: $showingPostActions) {
            if let currentUserId = APIClient.shared.currentUserId, currentUserId == post.user.id {
                Button("削除", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } else {
                Button("報告", role: .destructive) {
                    showingReportPostSheet = true
                }
            }
            Button("キャンセル", role: .cancel) { }
        }
        .alert("投稿を削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                Task {
                    await deletePost()
                }
            }
        } message: {
            Text("この投稿を削除してもよろしいですか？")
        }
        .overlay(
            Group {
                if showingComments {
                    CommentsOverlayView(
                        post: post,
                        isPresented: $showingComments,
                        onReport: { comment in
                            // Set comment first
                            commentToReport = comment
                            // Close comments overlay
                            showingComments = false
                            // Then show report sheet after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingReportCommentSheet = true
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
        )
    }

    private func togglePlayback() async {
        if isPlaying {
            musicPlayer.stopPreview()
            playbackStateManager.stopPlayback()
        } else {
            guard let previewUrl = post.previewUrl else {
                print("❌ No preview URL available")
                return
            }

            do {
                // Stop any currently playing post
                musicPlayer.stopPreview()

                // Start playback for this post
                try await musicPlayer.playPreviewFromURL(previewUrl, startTime: post.startTime)
                playbackStateManager.startPlayback(for: post.id)

                // Auto-stop after duration
                let duration = post.endTime - post.startTime
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    if playbackStateManager.currentlyPlayingPostId == post.id {
                        musicPlayer.stopPreview()
                        playbackStateManager.stopPlayback()
                    }
                }
            } catch {
                print("❌ Failed to play preview: \(error)")
            }
        }
    }

    private func toggleLike() async {
        // Optimistic update
        let wasLiked = isLiked
        likeStateManager.toggleLike(postId: post.id)

        do {
            if isLiked {
                try await APIClient.shared.likePost(postId: post.id)
            } else {
                try await APIClient.shared.unlikePost(postId: post.id)
            }
        } catch {
            // Revert on error
            if wasLiked != isLiked {
                likeStateManager.toggleLike(postId: post.id)
            }
            print("❌ Failed to toggle like: \(error)")
        }
    }

    private func deletePost() async {
        do {
            print("🔄 Attempting to delete post: \(post.id)")
            try await APIClient.shared.deletePost(postId: post.id)
            print("✅ Post deleted successfully")
            // Call the onDelete callback to refresh the feed
            onDelete?()
        } catch let error as APIError {
            switch error {
            case .invalidResponse(let statusCode, let data):
                let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No data"
                print("❌ Failed to delete post - Status: \(statusCode), Response: \(responseBody)")
            case .unauthorized:
                print("❌ Failed to delete post - Unauthorized")
            default:
                print("❌ Failed to delete post: \(error)")
            }
        } catch {
            print("❌ Failed to delete post: \(error)")
        }
    }
}

// Waveform animation view
struct WaveformView: View {
    @State private var animationValues: [CGFloat] = Array(repeating: 0.3, count: 5)
    let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 4, height: animationValues[index] * 50)
                    .animation(.easeInOut(duration: 0.3), value: animationValues[index])
            }
        }
        .onReceive(timer) { _ in
            for index in 0..<5 {
                animationValues[index] = CGFloat.random(in: 0.3...1.0)
            }
        }
    }
}

// Comments overlay view
struct CommentsOverlayView: View {
    let post: Post
    @Binding var isPresented: Bool
    let onReport: (Comment) -> Void
    @ObservedObject private var commentStateManager = CommentStateManager.shared
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var showingDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var keyboardHeight: CGFloat = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                        withAnimation {
                            isPresented = false
                        }
                    }

                // Comments list container (70% height, fixed)
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 0) {
                        // Header with drag indicator
                        VStack(spacing: 8) {
                            // Drag indicator
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 5)
                                .padding(.top, 8)

                            HStack {
                                Text("コメント")
                                    .font(.system(size: 18, weight: .bold))
                                Spacer()
                                Button(action: {
                                    hideKeyboard()
                                    withAnimation {
                                        isPresented = false
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        .background(Color(.systemBackground))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if value.translation.height > 0 {
                                        dragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if value.translation.height > 100 {
                                        hideKeyboard()
                                        withAnimation {
                                            isPresented = false
                                        }
                                    } else {
                                        withAnimation {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )

                        Divider()

                        // Comments list
                        if isLoading && comments.isEmpty {
                            Spacer()
                            ProgressView()
                            Spacer()
                        } else if comments.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("コメントがありません")
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(comments) { comment in
                                        CommentRowView(
                                            comment: comment,
                                            onDelete: {
                                                commentToDelete = comment
                                                showingDeleteAlert = true
                                            },
                                            onReport: {
                                                onReport(comment)
                                            }
                                        )
                                    }
                                }
                                .padding()
                                .padding(.bottom, 80)
                            }
                        }
                    }
                    .frame(height: geometry.size.height * 0.7)
                    .background(Color(.systemBackground))
                    .cornerRadius(20, corners: [.topLeft, .topRight])
                    .offset(y: dragOffset)
                }
                .ignoresSafeArea()

                // Comment input (separate layer, above keyboard)
                VStack {
                    Spacer()

                    TextField("コメントを入力...", text: $newCommentText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit {
                            Task {
                                await postComment()
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: -2)
                        .padding(.horizontal)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 8))
                }
                .offset(y: dragOffset - keyboardHeight)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
        .task {
            await loadComments()
        }
        .alert("コメントを削除", isPresented: $showingDeleteAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                Task {
                    await deleteComment()
                }
            }
        } message: {
            Text("このコメントを削除してもよろしいですか？")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reset animation states when app returns to foreground
            dragOffset = 0
        }
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation {
                keyboardHeight = 0
            }
        }
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func loadComments() async {
        isLoading = true
        do {
            let loadedComments = try await APIClient.shared.getComments(postId: post.id)
            // Sort by oldest first
            comments = loadedComments.sorted { $0.createdAt < $1.createdAt }
            print("✅ Loaded \(comments.count) comments")
        } catch {
            print("❌ Failed to load comments: \(error)")
        }
        isLoading = false
    }

    private func postComment() async {
        guard !newCommentText.isEmpty else { return }

        let content = newCommentText
        newCommentText = ""

        do {
            let request = CreateCommentRequest(postId: post.id, content: content)
            let newComment = try await APIClient.shared.createComment(request: request)
            // Add new comment at the end (newest at bottom)
            comments.append(newComment)
            commentStateManager.incrementCount(postId: post.id)
            print("✅ Comment posted successfully")
        } catch {
            print("❌ Failed to post comment: \(error)")
            newCommentText = content // Restore text on error
        }
    }

    private func deleteComment() async {
        guard let comment = commentToDelete else { return }

        do {
            try await APIClient.shared.deleteComment(commentId: comment.id)
            comments.removeAll { $0.id == comment.id }
            commentStateManager.decrementCount(postId: post.id)
            print("✅ Comment deleted successfully")
        } catch {
            print("❌ Failed to delete comment: \(error)")
        }
    }
}

// Extension for corner radius on specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Comment row view
struct CommentRowView: View {
    let comment: Comment
    let onDelete: () -> Void
    let onReport: () -> Void
    @State private var showingActions = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // User avatar
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(comment.user.displayName.prefix(1)))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Username and time
                HStack {
                    Text(comment.user.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text("@\(comment.user.username)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(timeAgoString(from: comment.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                // Comment content
                Text(comment.content)
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // More button
            Button(action: {
                showingActions = true
            }) {
                Image(systemName: "ellipsis")
                    .foregroundColor(.gray)
            }
            .confirmationDialog("", isPresented: $showingActions) {
                if let currentUserId = APIClient.shared.currentUserId, currentUserId == comment.user.id {
                    Button("削除", role: .destructive) {
                        onDelete()
                    }
                } else {
                    Button("報告", role: .destructive) {
                        onReport()
                    }
                }
                Button("キャンセル", role: .cancel) { }
            }
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "たった今"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))分前"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))時間前"
        } else {
            return "\(Int(seconds / 86400))日前"
        }
    }
}

#Preview {
    FeedView(refreshTrigger: .constant(false))
}
