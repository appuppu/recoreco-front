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
            } else if viewModel.userPosts.isEmpty && viewModel.currentUserPosts == nil {
                VStack(spacing: 20) {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.4))
                    Text("投稿がありません")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                    Text("ユーザーをフォローして音楽を共有しましょう")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            } else {
                // Current user's posts with horizontal navigation for other users
                AllUserPostsView(
                    allUserPosts: viewModel.userPosts,
                    currentUserPosts: viewModel.currentUserPosts,
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
    let currentUserPosts: UserPosts?
    let onRefresh: () -> Void
    @State private var currentUserIndex = 0
    @State private var horizontalDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            Color.black
                .ignoresSafeArea()
                .overlay(
                    ZStack {
                        if let currentUserPosts = currentUserPosts {
                            // 3D rotation logic for horizontal swipe (Y-axis):
                            // Swipe left (negative drag): current rotates to -90°, next enters from +90° to 0°
                            // Swipe right (positive drag): current rotates to +90°, previous enters from -90° to 0°
                            let normalizedHorizontalProgress = horizontalDragOffset / screenWidth
                            let clampedHorizontalProgress = max(-1.0, min(1.0, normalizedHorizontalProgress))

                            // Current screen rotation angle (0° to ±90°)
                            let currentHorizontalRotation = -clampedHorizontalProgress * 90.0

                            // Previous user (visible when swiping right - positive drag)
                            if clampedHorizontalProgress > 0 && !allUserPosts.isEmpty {
                                let previousIndex = (currentUserIndex - 1 + allUserPosts.count) % allUserPosts.count
                                // Previous starts at -90° and rotates to 0° as swipe progresses
                                let previousHorizontalRotation = -90.0 + (clampedHorizontalProgress * 90.0)
                                UserPostsScrollView(userPosts: allUserPosts[previousIndex], isCurrent: false, onRefresh: onRefresh)
                                    .frame(width: screenWidth, height: screenHeight)
                                    .rotation3DEffect(
                                        .degrees(previousHorizontalRotation),
                                        axis: (x: 0.0, y: 1.0, z: 0.0),
                                        perspective: 1.0
                                    )
                            }

                            // Current user's posts (main view)
                            UserPostsScrollView(userPosts: currentUserPosts, isCurrent: true, onRefresh: onRefresh)
                                .frame(width: screenWidth, height: screenHeight)
                                .rotation3DEffect(
                                    .degrees(currentHorizontalRotation),
                                    axis: (x: 0.0, y: 1.0, z: 0.0),
                                    perspective: 1.0
                                )

                            // Next user (visible when swiping left - negative drag)
                            if clampedHorizontalProgress < 0 && !allUserPosts.isEmpty {
                                let nextIndex = (currentUserIndex + 1) % allUserPosts.count
                                // Next starts at +90° and rotates to 0° as swipe progresses
                                let nextHorizontalRotation = 90.0 + (clampedHorizontalProgress * 90.0)
                                UserPostsScrollView(userPosts: allUserPosts[nextIndex], isCurrent: false, onRefresh: onRefresh)
                                    .frame(width: screenWidth, height: screenHeight)
                                    .rotation3DEffect(
                                        .degrees(nextHorizontalRotation),
                                        axis: (x: 0.0, y: 1.0, z: 0.0),
                                        perspective: 1.0
                                    )
                            }
                        }
                    }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
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
                            let horizontalAmount = abs(value.translation.width)
                            let verticalAmount = abs(value.translation.height)

                            // Only handle horizontal swipes here
                            if horizontalAmount > verticalAmount {
                                let threshold = screenWidth * 0.15
                                let velocity = value.predictedEndTranslation.width - value.translation.width

                                if !allUserPosts.isEmpty {
                                    if value.translation.width < -threshold || velocity < -500 {
                                        // Swipe left - next user
                                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.25)) {
                                            currentUserIndex = (currentUserIndex + 1) % allUserPosts.count
                                            horizontalDragOffset = 0
                                        }
                                    } else if value.translation.width > threshold || velocity > 500 {
                                        // Swipe right - previous user
                                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.25)) {
                                            currentUserIndex = (currentUserIndex - 1 + allUserPosts.count) % allUserPosts.count
                                            horizontalDragOffset = 0
                                        }
                                    } else {
                                        // Return to center
                                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.25)) {
                                            horizontalDragOffset = 0
                                        }
                                    }
                                } else {
                                    withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.25)) {
                                        horizontalDragOffset = 0
                                    }
                                }
                            }
                        }
                )
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

                    // Current post - always rendered
                    PostCardView(post: userPosts.posts[currentPostIndex], isCurrent: true, onDelete: onRefresh)
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: dragOffset)
                        .zIndex(2)

                    // Next post - always rendered
                    PostCardView(post: userPosts.posts[nextIndex], isCurrent: false, onDelete: onRefresh)
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: screenHeight + dragOffset)
                        .zIndex(dragOffset < 0 ? 1 : 0)
                }
                .clipped()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
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
    }
}

struct PostCardView: View {
    let post: Post
    let isCurrent: Bool
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    private let playbackStateManager = PlaybackStateManager.shared
    private let musicPlayer = MusicKitManager.shared
    @State private var isLiked: Bool
    @State private var likeCount: Int
    @State private var isPlaying: Bool = false
    @State private var showingDeleteConfirmation = false

    init(post: Post, isCurrent: Bool, onDelete: (() -> Void)? = nil) {
        self.post = post
        self.isCurrent = isCurrent
        self.onDelete = onDelete
        _isLiked = State(initialValue: post.isLiked ?? false)
        _likeCount = State(initialValue: post.likeCount ?? 0)
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

                        // Three-dot menu button (top-right) - only for own posts
                        if let currentUserId = APIClient.shared.currentUserId, currentUserId == post.user.id {
                            VStack {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        showingDeleteConfirmation = true
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
                        }

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

                // Action buttons (Like and Comment)
                HStack(spacing: 40) {
                    // Like button
                    Button(action: {
                        Task {
                            await toggleLike()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 22))
                                .foregroundColor(isLiked ? .red : .white)
                            Text("\(likeCount)")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }

                    // Comment button
                    Button(action: {
                        // TODO: Implement comment functionality
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 22))
                            Text("0")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 140)
            }
            .zIndex(1000)
            }
        }
        .onChange(of: isCurrent) { newValue in
            if !newValue && isPlaying {
                musicPlayer.stopPreview()
                playbackStateManager.stopPlayback()
                isPlaying = false
            }
        }
        .onDisappear {
            // Stop playback when post disappears
            if isPlaying {
                musicPlayer.stopPreview()
                playbackStateManager.stopPlayback()
                isPlaying = false
            }
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
    }

    private func togglePlayback() async {
        if isPlaying {
            musicPlayer.stopPreview()
            playbackStateManager.stopPlayback()
            isPlaying = false
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
                isPlaying = true

                // Auto-stop after duration
                let duration = post.endTime - post.startTime
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    if isPlaying {
                        musicPlayer.stopPreview()
                        playbackStateManager.stopPlayback()
                        isPlaying = false
                    }
                }
            } catch {
                print("❌ Failed to play preview: \(error)")
            }
        }
    }

    private func toggleLike() async {
        // Optimistic update
        let previousLiked = isLiked
        let previousCount = likeCount

        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        do {
            if isLiked {
                try await APIClient.shared.likePost(postId: post.id)
            } else {
                try await APIClient.shared.unlikePost(postId: post.id)
            }
        } catch {
            // Revert on error
            isLiked = previousLiked
            likeCount = previousCount
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

#Preview {
    FeedView(refreshTrigger: .constant(false))
}
