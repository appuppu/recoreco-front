import SwiftUI

// Shared timer coordinator for all radio buttons
class RadioButtonTimerCoordinator: ObservableObject {
    static let shared = RadioButtonTimerCoordinator()

    @Published var showingAlbumArt = true
    private var timer: Task<Void, Never>?

    private init() {
        startTimer()
    }

    func startTimer() {
        timer?.cancel()
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.8)) {
                            showingAlbumArt.toggle()
                        }
                    }
                }
            }
        }
    }

    func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @ObservedObject private var unreadPostsManager = UnreadPostsManager.shared
    @Binding var refreshTrigger: Bool
    @State private var showingMenu = false
    @State private var showingUserSearch = false
    @State private var showingCreatePost = false
    @State private var showingProfile = false
    @State private var postCreated = false
    @State private var showingNotifications = false
    @State private var unreadNotificationCount = 0
    @State private var unreadPostCounts: [Int64: Int] = [:]
    @State private var notificationPollingTask: Task<Void, Never>?
    @State private var userCurrentPostIndices: [Int64: Int] = [:] // userId -> currentPostIndex
    @State private var skipNextAutoPlay = false
    @State private var currentDisplayedUserIndex = 0
    @State private var showingOnboarding = false
    @State private var showingInteractiveTutorial = false
    @State private var tutorialStep: TutorialStep = .welcome
    @State private var createButtonFrame: CGRect = .zero
    @State private var wasTutorialPost = false // チュートリアル中の投稿かどうかを記録

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
                    Text("紹介がありません")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                    Text("紹介を作成するか、ユーザーをフォローして音楽を共有しましょう")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            } else {
                // All user posts with horizontal and vertical navigation
                AllUserPostsView(
                    allUserPosts: viewModel.allUserPosts,
                    skipNextAutoPlay: $skipNextAutoPlay,
                    currentDisplayedUserIndex: $currentDisplayedUserIndex,
                    onRefresh: {
                        Task {
                            await viewModel.refreshFeed()
                        }
                    }
                )
            }

            // Horizontal user radio buttons at top (fixed position, not affected by vertical scroll)
            if !viewModel.allUserPosts.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 70)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(viewModel.allUserPosts.enumerated()), id: \.element.id) { index, userPosts in
                                UserRadioButton(
                                    userPosts: userPosts,
                                    currentPostIndex: userCurrentPostIndices[userPosts.user.id] ?? 0,
                                    unreadCount: unreadPostCounts[userPosts.user.id] ?? 0,
                                    hasUnreadPosts: unreadPostsManager.hasUnreadPosts(in: userPosts.posts)
                                )
                                .frame(width: 60, height: 72)
                                .id("\(userPosts.user.id)-\(index)")
                                .onTapGesture {
                                    print("🎵 Radio button tapped for user: \(userPosts.user.displayName), index: \(index)")

                                            // Set skip flag immediately before any action
                                            skipNextAutoPlay = true
                                            print("🎵 Set skipNextAutoPlay flag to true")

                                            // Play music first
                                            if index < viewModel.allUserPosts.count {
                                                let targetUserPosts = viewModel.allUserPosts[index]
                                                let targetUserId = targetUserPosts.user.id
                                                let postIndex = userCurrentPostIndices[targetUserId] ?? 0

                                                if postIndex < targetUserPosts.posts.count,
                                                   let previewUrl = targetUserPosts.posts[postIndex].previewUrl {
                                                    let post = targetUserPosts.posts[postIndex]
                                                    let postId = post.id
                                                    print("🎵 Radio button: Target post: \(post.trackName), postId: \(postId)")

                                                    // Check if this post is already playing
                                                    if PlaybackStateManager.shared.currentlyPlayingPostId == postId {
                                                        print("🎵 Radio button: Post \(postId) is already playing, skipping re-play")
                                                    } else {
                                                        print("🎵 Radio button: Starting playback for post: \(post.trackName), postId: \(postId)")

                                                        Task {
                                                            do {
                                                                // Stop any currently playing post
                                                                MusicKitManager.shared.stopPreview()
                                                                print("🎵 Radio button: Stopped previous playback")

                                                                // Small delay for smooth transition
                                                                try? await Task.sleep(nanoseconds: 200_000_000)

                                                                // Start playback
                                                                try await MusicKitManager.shared.playPreviewFromURL(previewUrl, startTime: post.startTime)
                                                                PlaybackStateManager.shared.startPlayback(for: postId)
                                                                print("🎵 Radio button: Successfully started playback for postId: \(postId)")

                                                                // Auto-stop after duration
                                                                let duration = post.endTime - post.startTime
                                                                print("🎵 Radio button: Auto-stop scheduled in \(duration) seconds for postId: \(postId)")
                                                                Task {
                                                                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                                                                    if PlaybackStateManager.shared.currentlyPlayingPostId == postId {
                                                                        MusicKitManager.shared.stopPreview()
                                                                        PlaybackStateManager.shared.stopPlayback()
                                                                        print("🎵 Radio button: Auto-stopped playback for postId: \(postId)")
                                                                    } else {
                                                                        print("🎵 Radio button: Skipped auto-stop for postId: \(postId) (different song playing)")
                                                                    }
                                                                }
                                                            } catch {
                                                                print("🎵 Radio button: Failed to play music: \(error)")
                                                            }
                                                        }
                                                    }
                                                }

                                                // Mark posts as viewed
                                                Task {
                                                    do {
                                                        try await APIClient.shared.markPostsAsViewed(targetUserId: targetUserId)
                                                        await loadUnreadPostCounts()
                                                    } catch {
                                                        print("Failed to mark posts as viewed: \(error)")
                                                    }
                                                }
                                            }

                                            // Navigate to user's posts only if needed
                                            if currentDisplayedUserIndex != index {
                                                print("🎵 Radio button: Need to switch from user index \(currentDisplayedUserIndex) to \(index)")
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                                    print("🎵 Radio button: Sending ScrollToUser notification with skipAutoPlay=true")
                                                    NotificationCenter.default.post(
                                                        name: NSNotification.Name("ScrollToUser"),
                                                        object: nil,
                                                        userInfo: ["index": index, "skipAutoPlay": true]
                                                    )
                                                }
                                            } else {
                                                print("🎵 Radio button: Already displaying user index \(index), skipping screen transition")
                                            }

                                            // Reset flag after transition completes (longer delay)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                                skipNextAutoPlay = false
                                                print("🎵 Radio button: Reset skipNextAutoPlay flag to false")
                                            }
                                        }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 72)
                    .disabled(false)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(true)
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

            // Floating action buttons (bottom left and right)
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    // Left side: Menu button
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
                                FloatingMenuButton(icon: "plus", label: "紹介") {
                                    print("➕ Plus button tapped - current tutorialStep: \(tutorialStep)")
                                    if tutorialStep == .tapCreateButton {
                                        tutorialStep = .searchSong
                                        showingInteractiveTutorial = true
                                        wasTutorialPost = true // チュートリアル中の投稿であることを記録
                                        print("➕ Moved to searchSong step, marked as tutorial post")
                                    }
                                    showingCreatePost = true
                                    showingMenu = false
                                }
                                .captureFrame(in: $createButtonFrame)

                                // Search button
                                FloatingMenuButton(icon: "magnifyingglass", label: "ユーザー検索") {
                                    showingUserSearch = true
                                    showingMenu = false
                                }
                            }
                            .offset(y: -72)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Main menu button (fixed position)
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

                    // Right side: Notification button
                    Button(action: {
                        showingNotifications = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 56, height: 56)
                                .blur(radius: 10)

                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 56, height: 56)

                            Image(systemName: unreadNotificationCount > 0 ? "bell.badge.fill" : "bell.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)

                            // Badge for unread count
                            if unreadNotificationCount > 0 {
                                VStack {
                                    HStack {
                                        Spacer()
                                        ZStack {
                                            // Pulsing background
                                            Circle()
                                                .fill(Color.red.opacity(0.5))
                                                .frame(width: 24, height: 24)
                                                .scaleEffect(1.2)
                                                .opacity(0.6)
                                                .modifier(PulseAnimation())

                                            Text(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(4)
                                                .background(Color.red)
                                                .clipShape(Circle())
                                        }
                                        .offset(x: 10, y: -10)
                                    }
                                    Spacer()
                                }
                                .frame(width: 56, height: 56)
                            }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                }
            }

            // Interactive Tutorial Overlay
            if showingInteractiveTutorial && tutorialStep != .searchSong {
                InteractiveTutorialView(
                    isPresented: $showingInteractiveTutorial,
                    currentStep: $tutorialStep,
                    targetFrame: tutorialStep == .tapCreateButton ? createButtonFrame : nil,
                    onNext: {
                        if tutorialStep == .welcome {
                            tutorialStep = .tapCreateButton
                            // メニューを自動で開く
                            withAnimation {
                                showingMenu = true
                            }
                            // Warmup search in background for faster first search
                            Task {
                                await MusicKitManager.shared.warmupSearch()
                            }
                        } else if tutorialStep == .completed {
                            showingInteractiveTutorial = false
                            UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
                        }
                    }
                )
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
        .sheet(isPresented: $showingUserSearch, onDismiss: {
            Task {
                await viewModel.refreshFeed()
            }
        }) {
            UserSearchView()
        }
        .sheet(isPresented: $showingProfile, onDismiss: {
            Task {
                await viewModel.refreshFeed()
            }
        }) {
            ProfileView()
        }
        .sheet(isPresented: $showingNotifications, onDismiss: {
            Task {
                await loadUnreadCount()
            }
        }) {
            NotificationsView()
        }
        .fullScreenCover(isPresented: $showingCreatePost, onDismiss: {
            if postCreated {
                print("🎉 Post created, refreshing feed...")
                refreshTrigger.toggle()

                // チュートリアル中の投稿だった場合、フィード更新後に完了モーダルを表示
                if wasTutorialPost {
                    print("🎉 Tutorial post detected, will show completion modal after feed refresh")
                    // フィードの更新を待つ
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        print("🎉 Showing tutorial completion modal")
                        tutorialStep = .completed
                        showingInteractiveTutorial = true
                        wasTutorialPost = false // リセット
                        // UserDefaultsの設定は完了ボタンを押した時に行う
                    }
                }

                postCreated = false
            }
        }) {
            CreatePostView(postCreated: $postCreated, tutorialStep: $tutorialStep, showingInteractiveTutorial: $showingInteractiveTutorial)
        }
        .fullScreenCover(isPresented: $showingOnboarding, onDismiss: {
            // After onboarding is dismissed, check if we should show interactive tutorial
            if !UserDefaults.standard.bool(forKey: "hasCompletedTutorial") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingInteractiveTutorial = true
                    tutorialStep = .welcome
                }
            }
        }) {
            OnboardingView(isPresented: $showingOnboarding)
        }
        .task {
            await loadUnreadCount()
            await loadUnreadPostCounts()
        }
        .onAppear {
            startNotificationPolling()
            viewModel.startPolling()

            // Check if user has seen onboarding
            if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
                // Small delay to let the view load first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingOnboarding = true
                }
            }
            // Check if user has completed interactive tutorial
            else if !UserDefaults.standard.bool(forKey: "hasCompletedTutorial") {
                // Start interactive tutorial after onboarding
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showingInteractiveTutorial = true
                    tutorialStep = .welcome
                }
            }
        }
        .onDisappear {
            stopNotificationPolling()
            viewModel.stopPolling()
        }
        .onChange(of: showingNotifications) { isShowing in
            if isShowing {
                // Stop polling when notification view is open
                stopNotificationPolling()
            } else {
                // Resume polling when notification view is closed
                startNotificationPolling()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Foundation.Notification.Name("RefreshNotificationBadge"))) { _ in
            Task {
                await loadUnreadCount()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Foundation.Notification.Name("ReloadUnreadCounts"))) { _ in
            Task {
                await loadUnreadPostCounts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPost"))) { notification in
            if let userInfo = notification.userInfo,
               let postId = userInfo["postId"] as? Int64,
               let senderId = userInfo["senderId"] as? Int64 {
                // Find the user index in allUserPosts
                if let userIndex = viewModel.allUserPosts.firstIndex(where: { $0.user.id == senderId }) {
                    let userPosts = viewModel.allUserPosts[userIndex]

                    // Find the post index within this user's posts
                    if let postIndex = userPosts.posts.firstIndex(where: { $0.id == postId }) {
                        print("📬 Navigate to user \(userIndex), post \(postIndex) (postId: \(postId))")

                        // Navigate to that user's posts with specific post index
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ScrollToUser"),
                            object: nil,
                            userInfo: ["index": userIndex, "postIndex": postIndex]
                        )
                    } else {
                        print("⚠️ Post \(postId) not found in user's posts")
                    }
                } else {
                    print("⚠️ User \(senderId) not found in allUserPosts")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UpdateCurrentPostIndex"))) { notification in
            if let userInfo = notification.userInfo,
               let userId = userInfo["userId"] as? Int64,
               let postIndex = userInfo["postIndex"] as? Int {
                let oldIndex = userCurrentPostIndices[userId] ?? 0
                userCurrentPostIndices[userId] = postIndex
                print("📻 FeedView: Updated radio button post index for user \(userId): \(oldIndex) → \(postIndex)")

                // Find user display name for better logging
                if let userPosts = viewModel.allUserPosts.first(where: { $0.user.id == userId }) {
                    print("📻 FeedView: Radio button for \(userPosts.user.displayName) now shows post \(postIndex)")
                }
            }
        }
    }

    private func loadUnreadCount() async {
        do {
            unreadNotificationCount = try await APIClient.shared.getUnreadNotificationCount()
        } catch {
            print("Failed to load unread notification count: \(error)")
        }
    }

    private func loadUnreadPostCounts() async {
        do {
            let counts = try await APIClient.shared.getUnreadPostCounts()
            // Convert String keys to Int64
            unreadPostCounts = counts.reduce(into: [:]) { result, pair in
                if let userId = Int64(pair.key) {
                    result[userId] = pair.value
                }
            }
        } catch {
            print("Failed to load unread post counts: \(error)")
        }
    }

    private func startNotificationPolling() {
        // Cancel any existing polling task
        notificationPollingTask?.cancel()

        // Start new polling task
        notificationPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                if !Task.isCancelled {
                    print("📊 Polling for notifications and unread posts...")
                    await loadUnreadCount()
                    await loadUnreadPostCounts()
                }
            }
        }
    }

    private func stopNotificationPolling() {
        notificationPollingTask?.cancel()
        notificationPollingTask = nil
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
    @Binding var skipNextAutoPlay: Bool
    @Binding var currentDisplayedUserIndex: Int
    let onRefresh: () -> Void
    @State private var currentUserIndex = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var isAnimating = false
    @State private var skipAutoPlay = false

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            ZStack {
                Color.black
                    .ignoresSafeArea()

                // Main content with horizontal slide (same as vertical)
                if !allUserPosts.isEmpty {
                    ZStack {
                        let previousIndex = (currentUserIndex - 1 + allUserPosts.count) % allUserPosts.count
                        let nextIndex = (currentUserIndex + 1) % allUserPosts.count

                        // Previous user - always rendered (on the left)
                        if previousIndex < allUserPosts.count {
                            UserPostsScrollView(userPosts: allUserPosts[previousIndex], isCurrent: false, skipAutoPlay: $skipAutoPlay, onRefresh: onRefresh)
                                .frame(width: screenWidth, height: screenHeight)
                                .offset(x: -screenWidth + horizontalDragOffset)
                                .zIndex(horizontalDragOffset > 0 ? 1 : 0)
                                .id("\(allUserPosts[previousIndex].id)-\(previousIndex)")
                        }

                        // Current user - always rendered
                        UserPostsScrollView(userPosts: allUserPosts[currentUserIndex], isCurrent: true, skipAutoPlay: $skipAutoPlay, onRefresh: onRefresh)
                            .frame(width: screenWidth, height: screenHeight)
                            .offset(x: horizontalDragOffset)
                            .zIndex(2)
                            .id("\(allUserPosts[currentUserIndex].id)-\(currentUserIndex)")

                        // Next user - always rendered (on the right)
                        if nextIndex < allUserPosts.count {
                            UserPostsScrollView(userPosts: allUserPosts[nextIndex], isCurrent: false, skipAutoPlay: $skipAutoPlay, onRefresh: onRefresh)
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
                                            guard !allUserPosts.isEmpty else {
                                                isAnimating = false
                                                return
                                            }
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
                                            guard !allUserPosts.isEmpty else {
                                                isAnimating = false
                                                return
                                            }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToUser"))) { notification in
            if let index = notification.userInfo?["index"] as? Int {
                print("📻 ScrollToUser notification received - target index: \(index), current index: \(currentUserIndex), skipNextAutoPlay: \(skipNextAutoPlay)")

                // Validate index is within bounds
                guard index >= 0 && index < allUserPosts.count else {
                    print("⚠️ ScrollToUser: Invalid index \(index) for allUserPosts count \(allUserPosts.count)")
                    return
                }

                // Check if skipAutoPlay flag is set (from notification or binding)
                if skipNextAutoPlay || (notification.userInfo?["skipAutoPlay"] as? Bool ?? false) {
                    skipAutoPlay = true
                    print("📻 skipAutoPlay flag set to true")
                } else {
                    skipAutoPlay = false
                }

                withAnimation(.easeInOut(duration: 0.3)) {
                    currentUserIndex = index
                }
                print("📻 Updated currentUserIndex to: \(currentUserIndex)")

                // If postIndex is specified, send ScrollToPost notification after user transition
                if let postIndex = notification.userInfo?["postIndex"] as? Int,
                   index < allUserPosts.count {
                    print("📻 Will scroll to post index: \(postIndex)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        // Double-check array bounds before accessing
                        guard index < allUserPosts.count else {
                            print("⚠️ Index \(index) out of bounds for allUserPosts (count: \(allUserPosts.count))")
                            return
                        }
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ScrollToPost"),
                            object: nil,
                            userInfo: ["postIndex": postIndex, "userId": allUserPosts[index].user.id]
                        )
                    }
                }

                // Reset skipAutoPlay flag after animation and music starts
                if skipAutoPlay {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        skipAutoPlay = false
                        print("📻 AllUserPostsView: skipAutoPlay flag reset to false")
                    }
                }
            }
        }
        .onChange(of: allUserPosts.count) { newCount in
            print("⚠️ AllUserPostsView: allUserPosts count changed to \(newCount), currentUserIndex: \(currentUserIndex)")
            // Reset currentUserIndex if it's out of bounds
            if newCount == 0 {
                currentUserIndex = 0
                print("⚠️ AllUserPostsView: Reset currentUserIndex to 0 (empty array)")
            } else if currentUserIndex >= newCount {
                currentUserIndex = 0
                print("⚠️ AllUserPostsView: Reset currentUserIndex to 0 (was out of bounds: \(currentUserIndex) >= \(newCount))")
            }
        }
        .onChange(of: currentUserIndex) { newIndex in
            currentDisplayedUserIndex = newIndex
            print("📻 AllUserPostsView: Updated currentDisplayedUserIndex to \(newIndex)")
        }
        .onAppear {
            if !allUserPosts.isEmpty {
                currentDisplayedUserIndex = currentUserIndex
                print("📻 AllUserPostsView: Initialized currentDisplayedUserIndex to \(currentUserIndex)")
            } else {
                print("⚠️ AllUserPostsView: allUserPosts is empty, not setting currentDisplayedUserIndex")
            }
        }
    }
}

// Vertical scroll view for a user's posts with simple swipe
struct UserPostsScrollView: View {
    let userPosts: UserPosts
    let isCurrent: Bool
    @Binding var skipAutoPlay: Bool
    let onRefresh: () -> Void
    @State private var currentPostIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false
    @ObservedObject private var playbackStateManager = PlaybackStateManager.shared
    private let musicPlayer = MusicKitManager.shared

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
                            Text("紹介がありません")
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
                    PostCardView(
                        post: userPosts.posts[previousIndex],
                        isCurrent: false,
                        currentPostIndex: $currentPostIndex,
                        expectedIndex: previousIndex,
                        onDelete: onRefresh
                    )
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: -screenHeight + dragOffset)
                        .zIndex(dragOffset > 0 ? 1 : 0)
                        .id(userPosts.posts[previousIndex].id)

                    // Current post - always rendered
                    PostCardView(
                        post: userPosts.posts[currentPostIndex],
                        isCurrent: true,
                        currentPostIndex: $currentPostIndex,
                        expectedIndex: currentPostIndex,
                        onDelete: onRefresh
                    )
                        .frame(width: screenWidth, height: screenHeight)
                        .offset(y: dragOffset)
                        .zIndex(2)
                        .id(userPosts.posts[currentPostIndex].id)

                    // Next post - always rendered
                    PostCardView(
                        post: userPosts.posts[nextIndex],
                        isCurrent: false,
                        currentPostIndex: $currentPostIndex,
                        expectedIndex: nextIndex,
                        onDelete: onRefresh
                    )
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

                                    // Note: UpdateCurrentPostIndex notification will be sent by onChange(of: currentPostIndex)

                                    // Auto-play the new current post
                                    Task { @MainActor in
                                        await startPlaybackForCurrentPost()
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

                                    // Note: UpdateCurrentPostIndex notification will be sent by onChange(of: currentPostIndex)

                                    // Auto-play the new current post
                                    Task { @MainActor in
                                        await startPlaybackForCurrentPost()
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
        .onChange(of: isCurrent) { newValue in
            print("📻 UserPostsScrollView isCurrent changed to: \(newValue) for user: \(userPosts.user.displayName), postIndex: \(currentPostIndex), skipAutoPlay: \(skipAutoPlay)")

            if newValue {
                // Update radio button when this user becomes current
                NotificationCenter.default.post(
                    name: NSNotification.Name("UpdateCurrentPostIndex"),
                    object: nil,
                    userInfo: ["userId": userPosts.user.id, "postIndex": currentPostIndex]
                )
                print("📻 Sent UpdateCurrentPostIndex notification on isCurrent change: userId=\(userPosts.user.id), postIndex=\(currentPostIndex)")

                if !skipAutoPlay {
                    // Auto-play music when this user becomes current
                    print("📻 Starting playback for user: \(userPosts.user.displayName), post index: \(currentPostIndex)")
                    Task {
                        await startPlaybackForCurrentPost()
                    }
                } else {
                    print("📻 Skipping auto-play due to skipAutoPlay flag")
                }
            }
        }
        .onChange(of: currentPostIndex) { newIndex in
            // Update radio button when post index changes
            if isCurrent {
                print("📻 currentPostIndex changed to: \(newIndex) for user: \(userPosts.user.displayName)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("UpdateCurrentPostIndex"),
                    object: nil,
                    userInfo: ["userId": userPosts.user.id, "postIndex": newIndex]
                )
                print("📻 Sent UpdateCurrentPostIndex notification on postIndex change: userId=\(userPosts.user.id), postIndex=\(newIndex)")
            }
        }
        .onAppear {
            print("📻 UserPostsScrollView onAppear - isCurrent: \(isCurrent) for user: \(userPosts.user.displayName), postIndex: \(currentPostIndex), skipAutoPlay: \(skipAutoPlay)")

            // Always update radio button on appear
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateCurrentPostIndex"),
                object: nil,
                userInfo: ["userId": userPosts.user.id, "postIndex": currentPostIndex]
            )
            print("📻 Sent UpdateCurrentPostIndex notification on appear: userId=\(userPosts.user.id), postIndex=\(currentPostIndex)")

            if isCurrent && !skipAutoPlay {
                // Auto-play music when first displayed
                print("📻 Auto-playing on appear for user: \(userPosts.user.displayName)")
                Task {
                    await startPlaybackForCurrentPost()
                }
            } else if isCurrent && skipAutoPlay {
                print("📻 Skipping auto-play on appear due to skipAutoPlay flag")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToPost"))) { notification in
            if let userInfo = notification.userInfo,
               let targetPostIndex = userInfo["postIndex"] as? Int,
               let targetUserId = userInfo["userId"] as? Int64,
               targetUserId == userPosts.user.id {
                print("📬 ScrollToPost notification received for user \(userPosts.user.id), target post index: \(targetPostIndex)")

                // Scroll to the target post
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPostIndex = targetPostIndex
                }

                // Auto-play the target post
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000) // Wait for animation
                    await startPlaybackForCurrentPost()
                }
            }
        }
    }

    private func startPlaybackForCurrentPost() async {
        guard !userPosts.posts.isEmpty else {
            print("📻 No posts to play")
            return
        }

        let post = userPosts.posts[currentPostIndex]
        let postId = post.id
        print("📻 startPlaybackForCurrentPost - user: \(userPosts.user.displayName), post: \(post.trackName), postId: \(postId)")

        // Check if this post is already playing
        if playbackStateManager.currentlyPlayingPostId == postId {
            print("📻 Post \(postId) is already playing, skipping")
            return
        }

        guard let previewUrl = post.previewUrl else {
            print("📻 No preview URL for post")
            return
        }

        do {
            // Stop any currently playing post
            musicPlayer.stopPreview()
            print("📻 Stopped previous playback")

            // Small delay to ensure smooth transition
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            // Start playback for this post
            try await musicPlayer.playPreviewFromURL(previewUrl, startTime: post.startTime)
            playbackStateManager.startPlayback(for: postId)
            print("📻 Started playback for post: \(postId)")

            // Auto-stop after duration
            let duration = post.endTime - post.startTime
            print("📻 Auto-stop scheduled in \(duration) seconds for postId: \(postId)")
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if playbackStateManager.currentlyPlayingPostId == postId {
                    musicPlayer.stopPreview()
                    playbackStateManager.stopPlayback()
                    print("📻 Auto-stopped playback for post: \(postId)")
                } else {
                    print("📻 Skipped auto-stop for post: \(postId) (different song playing)")
                }
            }
        } catch {
            print("📻 Failed to start playback: \(error)")
        }
    }
}

struct PostCardView: View {
    let post: Post
    let isCurrent: Bool
    @Binding var currentPostIndex: Int
    let expectedIndex: Int
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
    @State private var showingUserProfile = false
    @State private var backgroundScale: CGFloat = 1.0
    @State private var backgroundRotation: Double = 0

    init(post: Post, isCurrent: Bool, currentPostIndex: Binding<Int>, expectedIndex: Int, onDelete: (() -> Void)? = nil) {
        self.post = post
        self.isCurrent = isCurrent
        self._currentPostIndex = currentPostIndex
        self.expectedIndex = expectedIndex
        self.onDelete = onDelete
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
            let albumSize: CGFloat = 340
            let albumLeftPadding = (screenWidth - albumSize) / 2

            ZStack(alignment: .bottom) {
                // Black background to prevent white background showing
                Color.black
                    .frame(width: screenWidth, height: screenHeight)
                    .zIndex(0)

                // Background artwork with blur and animation
                AsyncImage(url: URL(string: post.artworkUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: screenWidth, height: screenHeight)
                        .blur(radius: 50)
                        .scaleEffect(backgroundScale)
                        .rotationEffect(.degrees(backgroundRotation))
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
                        .scaleEffect(backgroundScale)
                        .rotationEffect(.degrees(backgroundRotation))
                }
                .allowsHitTesting(false)
                .zIndex(1)
                .onChange(of: isPlaying) { playing in
                    if playing {
                        startBackgroundAnimation()
                    } else {
                        stopBackgroundAnimation()
                    }
                }

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
                    Spacer().frame(height: 150)

                // Track info (top, single line with marquee)
                VStack(spacing: 0) {
                    let trackInfo = [post.trackName, post.artistName, post.albumName]
                        .compactMap { $0 }
                        .joined(separator: " / ")

                    MarqueeText(
                        text: trackInfo,
                        font: .system(size: 20, weight: .semibold),
                        color: .white,
                        frameWidth: albumSize
                    )
                    .frame(height: 30)
                }
                .padding(.horizontal, albumLeftPadding)
                .padding(.bottom, 6)

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
                                    .scaledToFill()
                                    .frame(width: albumSize, height: albumSize)
                                    .clipped()
                            case .failure:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            @unknown default:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                        }
                        .frame(width: albumSize, height: albumSize)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)

                        // Profile icon and name (top-left)
                        VStack {
                            HStack(spacing: 8) {
                                AsyncImage(url: URL(string: APIClient.shared.getFullImageURL(post.user.profileImageUrl) ?? "")) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(Color.white.opacity(0.3))
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.6))
                                        )
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                )
                                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                                .contentShape(Circle())
                                .onTapGesture {
                                    showingUserProfile = true
                                }

                                Text(post.user.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.5))
                                    )
                                    .lineLimit(1)
                                    .onTapGesture {
                                        showingUserProfile = true
                                    }

                                Spacer()
                            }
                            .padding(12)
                            Spacer()
                        }
                        .frame(width: albumSize, height: albumSize)

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
                        .frame(width: albumSize, height: albumSize)

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
                        .frame(width: albumSize, height: albumSize)

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
                                            // Show like count only for own posts
                                            if let currentUserId = APIClient.shared.currentUserId,
                                               post.user.id == currentUserId {
                                                Text("\(likeCount)")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
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
                        .frame(width: albumSize, height: albumSize)
                    }
                    .padding(.bottom, 20)

                    // Comment section
                    if let comment = post.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: Color.black.opacity(0.3), radius: 5, x: 0, y: 2)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 16)
                    }

                Spacer()
            }
            .zIndex(1000)
            }
        }
        .onAppear {
            // Initialize state managers
            LikeStateManager.shared.initialize(
                postId: post.id,
                isLiked: post.isLiked ?? false,
                count: post.likeCount ?? 0
            )
            CommentStateManager.shared.initialize(
                postId: post.id,
                count: post.commentCount ?? 0
            )

            // Mark as read when post becomes visible
            if isCurrent {
                UnreadPostsManager.shared.markAsRead(post.id)
            }
        }
        .onChange(of: isCurrent) { newValue in
            // Mark as read when post becomes current
            if newValue {
                UnreadPostsManager.shared.markAsRead(post.id)
            }
        }
        // Removed onDisappear to prevent stopping playback during screen transitions
        // Playback is automatically stopped when a new song starts playing (in playPreviewFromURL)
        .sheet(isPresented: $showingReportCommentSheet) {
            if let comment = commentToReport {
                ReportCommentView(comment: comment)
            }
        }
        .sheet(isPresented: $showingReportPostSheet) {
            ReportPostView(post: post)
        }
        .confirmationDialog("", isPresented: $showingPostActions) {
            // Apple Music link (always show)
            if let appleMusicUrl = post.appleMusicUrl, let url = URL(string: appleMusicUrl) {
                Button("Apple Musicで開く") {
                    UIApplication.shared.open(url)
                }
            }

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
        .alert("紹介を削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                Task {
                    await deletePost()
                }
            }
        } message: {
            Text("この紹介を削除してもよろしいですか？")
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
        .sheet(isPresented: $showingUserProfile) {
            NavigationView {
                UserProfileView(userId: post.user.id)
            }
        }
    }

    private func startPlayback() async {
        guard let previewUrl = post.previewUrl else { return }

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
            // Silently fail
        }
    }

    private func togglePlayback() async {
        if isPlaying {
            musicPlayer.stopPreview()
            playbackStateManager.stopPlayback()
        } else {
            await startPlayback()
        }
    }

    private func toggleLike() async {
        // Optimistic update
        let wasLiked = isLiked
        likeStateManager.toggleLike(postId: post.id)

        do {
            let response: APIClient.LikeResponse
            if isLiked {
                response = try await APIClient.shared.likePost(postId: post.id)
            } else {
                response = try await APIClient.shared.unlikePost(postId: post.id)
            }

            // Update with server response to ensure accuracy
            likeStateManager.updateFromServer(
                postId: post.id,
                isLiked: response.isLiked,
                count: response.likeCount
            )
            print("✅ Like toggled successfully: likeCount=\(response.likeCount), isLiked=\(response.isLiked)")
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

    private func startBackgroundAnimation() {
        // Breathing scale effect
        withAnimation(
            Animation
                .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
        ) {
            backgroundScale = 1.08
        }

        // Slow rotation
        withAnimation(
            Animation
                .linear(duration: 20.0)
                .repeatForever(autoreverses: false)
        ) {
            backgroundRotation = 360
        }
    }

    private func stopBackgroundAnimation() {
        withAnimation(.easeOut(duration: 0.5)) {
            backgroundScale = 1.0
            backgroundRotation = 0
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
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.9),
                                Color.red.opacity(0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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

// Marquee scrolling text view
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let frameWidth: CGFloat

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 40) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .fixedSize()

                // Duplicate text for seamless loop
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .fixedSize()
            }
            .background(
                GeometryReader { textGeometry in
                    Color.clear.onAppear {
                        textWidth = textGeometry.size.width
                    }
                }
            )
            .offset(x: offset)
            .onAppear {
                startScrolling()
            }
        }
        .frame(width: frameWidth)
        .clipped()
    }

    private func startScrolling() {
        // Only scroll if text is wider than frame
        guard textWidth > frameWidth else { return }

        // Calculate single text width (including spacing)
        let singleTextWidth = (textWidth + 40) / 2

        // Start from right edge
        offset = 0

        // Animate continuously
        let duration = Double(singleTextWidth / 25)

        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -singleTextWidth
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
    @State private var commentErrorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in }
                    )
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
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 20)
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
                        }
                    }
                    .frame(height: geometry.size.height * 0.7)
                    .background(Color(.systemBackground))
                    .cornerRadius(20, corners: [.topLeft, .topRight])
                    .offset(y: dragOffset)
                }
                .ignoresSafeArea()

                // Comment input (separate layer, above keyboard)
                VStack(spacing: 4) {
                    Spacer()

                    // Error message
                    if let errorMessage = commentErrorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }

                    TextField("コメントを入力...", text: $newCommentText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit {
                            Task {
                                await postComment()
                            }
                        }
                        .onChange(of: newCommentText) { _ in
                            // Clear error when user starts typing
                            if commentErrorMessage != nil {
                                commentErrorMessage = nil
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

        // Validate comment length
        if newCommentText.count > 20 {
            commentErrorMessage = "コメントは20文字以内で入力してください"
            return
        }

        let content = newCommentText
        newCommentText = ""
        commentErrorMessage = nil

        do {
            let request = CreateCommentRequest(postId: post.id, content: content)
            let newComment = try await APIClient.shared.createComment(request: request)
            // Add new comment at the end (newest at bottom)
            comments.append(newComment)
            commentStateManager.incrementCount(postId: post.id)
        } catch {
            commentErrorMessage = "コメントの投稿に失敗しました"
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
                    Text(comment.user.username)
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

// Pulse animation modifier for badges
struct PulseAnimation: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.3 : 1.0)
            .opacity(isAnimating ? 0 : 0.6)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// User radio button for horizontal scrolling
struct UserRadioButton: View {
    let userPosts: UserPosts
    let currentPostIndex: Int
    let unreadCount: Int
    let hasUnreadPosts: Bool

    @ObservedObject private var playbackStateManager = PlaybackStateManager.shared
    @ObservedObject private var timerCoordinator = RadioButtonTimerCoordinator.shared

    private var currentPost: Post? {
        guard currentPostIndex < userPosts.posts.count else {
            print("⚠️ Radio button for \(userPosts.user.displayName): currentPostIndex \(currentPostIndex) out of range (total: \(userPosts.posts.count)), using first post")
            return userPosts.posts.first
        }
        return userPosts.posts[currentPostIndex]
    }

    private var isPlaying: Bool {
        // Check if any of this user's posts is currently playing
        guard let currentlyPlayingId = playbackStateManager.currentlyPlayingPostId else {
            return false
        }
        return userPosts.posts.contains { $0.id == currentlyPlayingId }
    }

    var body: some View {
        VStack(spacing: 4) {
            // User name
            Text(userPosts.user.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .frame(width: 60, height: 14, alignment: .center)

            ZStack {
            // Main circle with border
            ZStack {
                // For discovery tab (user.id == -1), alternate between app icon and album art
                if userPosts.user.id == -1 {
                    if timerCoordinator.showingAlbumArt {
                        // Show album artwork
                        if let artworkUrl = currentPost?.artworkUrl,
                           let url = URL(string: artworkUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    placeholderView(isAlbumArt: true)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 54, height: 54)
                                        .clipShape(Circle())
                                case .failure:
                                    placeholderView(isAlbumArt: true)
                                @unknown default:
                                    placeholderView(isAlbumArt: true)
                                }
                            }
                        } else {
                            placeholderView(isAlbumArt: true)
                        }
                    } else {
                        // Show static app icon (when others show profile)
                        Image("DiscoveryIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                    }
                } else if timerCoordinator.showingAlbumArt {
                    // Album artwork
                    if let artworkUrl = currentPost?.artworkUrl,
                       let url = URL(string: artworkUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                placeholderView(isAlbumArt: true)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 54, height: 54)
                                    .clipShape(Circle())
                            case .failure:
                                placeholderView(isAlbumArt: true)
                            @unknown default:
                                placeholderView(isAlbumArt: true)
                            }
                        }
                    } else {
                        placeholderView(isAlbumArt: true)
                    }
                } else {
                    // Profile image
                    if let profileImageUrl = userPosts.user.profileImageUrl,
                       let url = URL(string: APIClient.shared.getFullImageURL(profileImageUrl) ?? "") {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                placeholderView(isAlbumArt: false)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 54, height: 54)
                                    .clipShape(Circle())
                            case .failure:
                                placeholderView(isAlbumArt: false)
                            @unknown default:
                                placeholderView(isAlbumArt: false)
                            }
                        }
                    } else {
                        placeholderView(isAlbumArt: false)
                    }
                }

                // Border with gradient - different color for unread posts
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: hasUnreadPosts ? [
                                Color.blue.opacity(0.9),
                                Color.cyan.opacity(0.9)
                            ] : [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: hasUnreadPosts ? 3 : 2
                    )
                    .frame(width: 54, height: 54)

                // Waveform animation when playing (inside the circle)
                if isPlaying {
                    MiniWaveformView()
                        .frame(width: 36, height: 24)
                        .transition(.opacity)
                }

                // Unread badge
                if unreadCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                // Pulsing background
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.purple.opacity(0.5),
                                                Color.blue.opacity(0.5)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 18, height: 18)
                                    .scaleEffect(1.2)
                                    .opacity(0.6)
                                    .modifier(PulseAnimation())

                                Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.purple,
                                                Color.blue
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(Circle())
                            }
                            .offset(x: 8, y: -8)
                        }
                        Spacer()
                    }
                    .frame(width: 54, height: 54)
                }
            }
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
    }

    private func placeholderView(isAlbumArt: Bool) -> some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 54, height: 54)
            .overlay(
                Image(systemName: isAlbumArt ? "music.note" : "person.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            )
    }
}

// Mini waveform for radio button
struct MiniWaveformView: View {
    @State private var animationValues: [CGFloat] = Array(repeating: 0.3, count: 3)
    let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.9),
                                Color.red.opacity(0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
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
