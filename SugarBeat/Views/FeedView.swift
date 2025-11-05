import SwiftUI
import UIKit

// Device type detection for iPad responsive design
enum DeviceType {
    case iPhone
    case iPad

    static var current: DeviceType {
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }

    static var isIPad: Bool {
        current == .iPad
    }

    static var isIPhone: Bool {
        current == .iPhone
    }
}

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
    @State private var isInitialLoad = true // アプリ起動時の初回のみ自動再生をスキップ
    @State private var lastInteractionTime = Date()
    @State private var showSwipeHint = false
    @State private var swipeHintTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Background color
            Color.black.ignoresSafeArea()

            // Content wrapper for iPad
            Group {
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
                VStack(spacing: DeviceType.isIPad ? 24 : 20) {
                    Image(systemName: "music.note")
                        .font(.system(size: DeviceType.isIPad ? 72 : 60))
                        .foregroundColor(.white.opacity(0.4))
                    Text("紹介がありません")
                        .font(DeviceType.isIPad ? .title : .title2)
                        .foregroundColor(.white.opacity(0.7))
                    Text("紹介を作成するか、ユーザーをフォローして音楽を共有しましょう")
                        .font(DeviceType.isIPad ? .body : .caption)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            } else {
                // All user posts with horizontal and vertical navigation
                AllUserPostsView(
                    allUserPosts: viewModel.allUserPosts,
                    skipNextAutoPlay: $skipNextAutoPlay,
                    currentDisplayedUserIndex: $currentDisplayedUserIndex,
                    isInitialLoad: $isInitialLoad,
                    showSwipeHint: $showSwipeHint,
                    onRefresh: {
                        Task {
                            await viewModel.refreshFeed()
                        }
                    },
                    onInteraction: {
                        resetSwipeHintTimer()
                    }
                )
            }
            }
            .frame(maxWidth: DeviceType.isIPad ? 700 : .infinity)

            // Horizontal user radio buttons at top (fixed position, not affected by vertical scroll)
            if !viewModel.allUserPosts.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: DeviceType.isIPad ? 90 : 70)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DeviceType.isIPad ? 16 : 12) {
                            ForEach(Array(viewModel.allUserPosts.enumerated()), id: \.element.id) { index, userPosts in
                                HStack(spacing: 8) {
                                    UserRadioButton(
                                        userPosts: userPosts,
                                        currentPostIndex: userCurrentPostIndices[userPosts.user.id] ?? 0,
                                        unreadCount: unreadPostCounts[userPosts.user.id] ?? 0,
                                        hasUnreadPosts: userPosts.user.id == -1
                                            ? viewModel.hasUnreadDiscoveryPosts
                                            : (viewModel.usersWithUnreadPosts.contains(userPosts.user.id) || unreadPostsManager.hasUnreadPosts(in: userPosts.posts))
                                    )
                                    .frame(width: DeviceType.isIPad ? 80 : 60, height: DeviceType.isIPad ? 92 : 72)
                                    .id("\(userPosts.user.id)-\(index)")
                                    .onTapGesture {
                                        // Reset swipe hint timer on interaction
                                        resetSwipeHintTimer()

                                        // User interaction detected - disable initial load flag
                                            if isInitialLoad {
                                                isInitialLoad = false
                                            }

                                            // Set skip flag immediately before any action
                                            skipNextAutoPlay = true

                                            // Play music first
                                            if index < viewModel.allUserPosts.count {
                                                let targetUserPosts = viewModel.allUserPosts[index]
                                                let targetUserId = targetUserPosts.user.id
                                                let postIndex = userCurrentPostIndices[targetUserId] ?? 0

                                                if postIndex < targetUserPosts.posts.count,
                                                   let previewUrl = targetUserPosts.posts[postIndex].previewUrl {
                                                    let post = targetUserPosts.posts[postIndex]
                                                    let postId = post.id

                                                    // Check if this post is already playing in the same context
                                                    if PlaybackStateManager.shared.currentlyPlayingPostId == postId &&
                                                       PlaybackStateManager.shared.currentlyPlayingUserId == targetUserId {
                                                        // Already playing, skip
                                                    } else {

                                                        Task {
                                                            do {
                                                                // Stop any currently playing post
                                                                MusicKitManager.shared.stopPreview()

                                                                // Small delay for smooth transition
                                                                try? await Task.sleep(nanoseconds: 200_000_000)

                                                                // Start playback
                                                                try await MusicKitManager.shared.playPreviewFromURL(previewUrl, startTime: post.startTime)
                                                                await MainActor.run {
                                                                    PlaybackStateManager.shared.startPlayback(for: postId, userId: targetUserId)
                                                                }

                                                                // Auto-stop after duration
                                                                let duration = post.endTime - post.startTime
                                                                Task {
                                                                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                                                                    await MainActor.run {
                                                                        if PlaybackStateManager.shared.currentlyPlayingPostId == postId {
                                                                            MusicKitManager.shared.stopPreview()
                                                                            PlaybackStateManager.shared.stopPlayback()
                                                                        }
                                                                    }
                                                                }
                                                            } catch {
                                                                // Silently fail
                                                            }
                                                        }
                                                    }
                                                }

                                                // Mark posts as viewed and read
                                                Task {
                                                    // Mark all posts in this tab as read locally (for Discovery)
                                                    for post in targetUserPosts.posts {
                                                        unreadPostsManager.markAsRead(post.id)
                                                    }

                                                    // Clear Discovery unread flag if this is the Discovery tab
                                                    if targetUserId == -1 {
                                                        viewModel.hasUnreadDiscoveryPosts = false
                                                    } else {
                                                        // Clear unread flag for this user
                                                        viewModel.usersWithUnreadPosts.remove(targetUserId)
                                                    }

                                                    // Mark as viewed on server (for mutual follows)
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
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                                    NotificationCenter.default.post(
                                                        name: NSNotification.Name("ScrollToUser"),
                                                        object: nil,
                                                        userInfo: ["index": index, "skipAutoPlay": true]
                                                    )
                                                }
                                            }

                                            // Reset flag after transition completes (longer delay)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                                skipNextAutoPlay = false
                                            }
                                        }

                                    // Show message for current user when no follows
                                    if userPosts.user.id == APIClient.shared.currentUserId && viewModel.allUserPosts.count <= 2 {
                                        Text("他のユーザーと繋がると\nここに表示されます。")
                                            .font(.system(size: DeviceType.isIPad ? 13 : 11))
                                            .foregroundColor(.white.opacity(0.7))
                                            .multilineTextAlignment(.leading)
                                            .lineSpacing(2)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.black.opacity(0.5))
                                            )
                                            .frame(width: 160)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DeviceType.isIPad ? 32 : 20)
                    }
                    .frame(height: DeviceType.isIPad ? 92 : 72)
                    .disabled(false)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(true)
            }

            // Dark overlay when menu is shown
            if showingMenu {
                Color.black.opacity(0.8)
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
                            VStack(alignment: .leading, spacing: DeviceType.isIPad ? 20 : 16) {
                                // Profile button
                                FloatingMenuButton(icon: "person", label: "プロフィール") {
                                    showingProfile = true
                                    showingMenu = false
                                }

                                // Post button
                                FloatingMenuButton(icon: "plus", label: "おすすめの音楽紹介") {
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
                            .offset(y: DeviceType.isIPad ? -90 : -72)
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
                                    .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)
                                    .blur(radius: 10)

                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)

                                Image(systemName: showingMenu ? "xmark" : "ellipsis")
                                    .font(.system(size: DeviceType.isIPad ? 24 : 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .rotationEffect(.degrees(showingMenu ? 0 : 90))
                            }
                        }
                        .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)
                    }
                    .padding(.leading, DeviceType.isIPad ? 32 : 20)
                    .padding(.bottom, DeviceType.isIPad ? 120 : 100)

                    Spacer()

                    // Right side: Notification button
                    Button(action: {
                        showingNotifications = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)
                                .blur(radius: 10)

                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)

                            Image(systemName: unreadNotificationCount > 0 ? "bell.badge.fill" : "bell.fill")
                                .font(.system(size: DeviceType.isIPad ? 26 : 22, weight: .semibold))
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
                                                .frame(width: DeviceType.isIPad ? 28 : 24, height: DeviceType.isIPad ? 28 : 24)
                                                .scaleEffect(1.2)
                                                .opacity(0.6)
                                                .modifier(PulseAnimation())

                                            Text(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")
                                                .font(.system(size: DeviceType.isIPad ? 12 : 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(4)
                                                .background(Color.red)
                                                .clipShape(Circle())
                                        }
                                        .offset(x: 10, y: -10)
                                    }
                                    Spacer()
                                }
                                .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)
                            }
                        }
                    }
                    .frame(width: DeviceType.isIPad ? 70 : 56, height: DeviceType.isIPad ? 70 : 56)
                    .padding(.trailing, DeviceType.isIPad ? 32 : 20)
                    .padding(.bottom, DeviceType.isIPad ? 120 : 100)
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
            print("🔍 CreatePost dismissed, postCreated: \(postCreated)")
            if postCreated {
                print("🎉 Post created, refreshing feed...")

                // Reset swipe hint timer after post creation
                resetSwipeHintTimer()

                // 投稿後、自分のタブを表示するため、現在のユーザーIDを保存
                let currentUserId = APIClient.shared.currentUserId
                print("🔍 Current user ID: \(currentUserId ?? -999)")

                refreshTrigger.toggle()

                // フィード更新が完了するまで待ってから、自分のタブに移動
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🔍 All user posts count after refresh: \(viewModel.allUserPosts.count)")
                    for (index, userPosts) in viewModel.allUserPosts.enumerated() {
                        print("🔍 Index \(index): userId=\(userPosts.user.id), displayName=\(userPosts.user.displayName)")
                    }

                    if let userId = currentUserId {
                        if let userIndex = viewModel.allUserPosts.firstIndex(where: { $0.user.id == userId }) {
                            print("🔍 Found current user at index: \(userIndex)")
                            print("🔍 Before update - currentDisplayedUserIndex: \(currentDisplayedUserIndex)")
                            currentDisplayedUserIndex = userIndex
                            print("🔍 After update - currentDisplayedUserIndex: \(currentDisplayedUserIndex)")
                        } else {
                            print("🔍 ❌ Could not find current user in allUserPosts")
                        }
                    } else {
                        print("🔍 ❌ Current user ID is nil")
                    }
                }

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
            startSwipeHintTimer()

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
            swipeHintTask?.cancel()
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
                _ = userCurrentPostIndices[userId] ?? 0
                userCurrentPostIndices[userId] = postIndex

                // Find user display name for better logging
                _ = viewModel.allUserPosts.first(where: { $0.user.id == userId })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FollowStatusChanged"))) { _ in
            // Refresh feed when follow status changes
            Task {
                refreshTrigger.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PublicStatusChanged"))) { _ in
            // Refresh feed when public status changes
            Task {
                refreshTrigger.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserBlocked"))) { notification in
            // Remove blocked user from feed immediately
            if let userInfo = notification.userInfo,
               let blockedUserId = userInfo["blockedUserId"] as? Int64 {

                // Check if currently viewing this user before removal
                let wasViewingBlockedUser = currentDisplayedUserIndex < viewModel.allUserPosts.count &&
                                           viewModel.allUserPosts[currentDisplayedUserIndex].user.id == blockedUserId

                // Remove user from allUserPosts
                viewModel.allUserPosts.removeAll { $0.user.id == blockedUserId }

                // Remove from discovery feed as well
                if let discoveryIndex = viewModel.allUserPosts.firstIndex(where: { $0.user.id == -1 }) {
                    var discoveryPosts = viewModel.allUserPosts[discoveryIndex]
                    discoveryPosts.posts.removeAll { $0.user.id == blockedUserId }
                    viewModel.allUserPosts[discoveryIndex] = discoveryPosts
                }

                // If was viewing this user or index is now out of range, navigate to first user (Discovery)
                if wasViewingBlockedUser || currentDisplayedUserIndex >= viewModel.allUserPosts.count {
                    currentDisplayedUserIndex = 0
                    // Notify AllUserPostsView to update its currentUserIndex
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ScrollToUser"),
                        object: nil,
                        userInfo: ["index": 0, "skipAutoPlay": true]
                    )
                }

                print("🚫 Blocked user \(blockedUserId) removed from feed")
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

    private func resetSwipeHintTimer() {
        lastInteractionTime = Date()
        showSwipeHint = false
        swipeHintTask?.cancel()
        startSwipeHintTimer()
    }

    private func startSwipeHintTimer() {
        swipeHintTask?.cancel()
        swipeHintTask = Task {
            try? await Task.sleep(nanoseconds: 40_000_000_000) // 40 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSwipeHint = true
                    }
                }
            }
        }
    }
}

struct FloatingMenuButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DeviceType.isIPad ? 16 : 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: DeviceType.isIPad ? 56 : 44, height: DeviceType.isIPad ? 56 : 44)
                        .blur(radius: 8)

                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: DeviceType.isIPad ? 56 : 44, height: DeviceType.isIPad ? 56 : 44)

                    Image(systemName: icon)
                        .font(.system(size: DeviceType.isIPad ? 22 : 18, weight: .medium))
                        .foregroundColor(.white)
                }

                Text(label)
                    .font(.system(size: DeviceType.isIPad ? 16 : 14, weight: .medium))
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
    @Binding var isInitialLoad: Bool
    @Binding var showSwipeHint: Bool
    let onRefresh: () -> Void
    let onInteraction: () -> Void
    @State private var currentUserIndex = 0
    @State private var horizontalDragOffset: CGFloat = 0
    @State private var isAnimating = false
    @State private var skipAutoPlay = false
    @State private var hasInitialized = false

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
                            UserPostsScrollView(userPosts: allUserPosts[previousIndex], isCurrent: false, skipAutoPlay: $skipAutoPlay, isInitialLoad: isInitialLoad, onRefresh: onRefresh)
                                .frame(width: screenWidth, height: screenHeight)
                                .offset(x: -screenWidth + horizontalDragOffset)
                                .zIndex(horizontalDragOffset > 0 ? 1 : 0)
                                .id("\(allUserPosts[previousIndex].id)-\(previousIndex)")
                        }

                        // Current user - always rendered
                        UserPostsScrollView(userPosts: allUserPosts[currentUserIndex], isCurrent: true, skipAutoPlay: $skipAutoPlay, isInitialLoad: isInitialLoad, onRefresh: onRefresh)
                            .frame(width: screenWidth, height: screenHeight)
                            .offset(x: horizontalDragOffset)
                            .zIndex(2)
                            .id("\(allUserPosts[currentUserIndex].id)-\(currentUserIndex)")

                        // Next user - always rendered (on the right)
                        if nextIndex < allUserPosts.count {
                            UserPostsScrollView(userPosts: allUserPosts[nextIndex], isCurrent: false, skipAutoPlay: $skipAutoPlay, isInitialLoad: isInitialLoad, onRefresh: onRefresh)
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

                                // User interaction detected
                                onInteraction()

                                // User interaction detected - disable initial load flag
                                if isInitialLoad {
                                    isInitialLoad = false
                                }

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

                                // User interaction detected
                                onInteraction()

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

                // Swipe hint overlay
                if showSwipeHint {
                    VStack {
                        Spacer()
                            .frame(height: screenHeight * 0.5)

                        SwipeHintView(showSwipeHint: $showSwipeHint)
                            .transition(.opacity)

                        Spacer()
                    }
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

                // Validate index is within bounds
                guard index >= 0 && index < allUserPosts.count else {
                    print("⚠️ ScrollToUser: Invalid index \(index) for allUserPosts count \(allUserPosts.count)")
                    return
                }

                // Check if skipAutoPlay flag is set (from notification or binding)
                if skipNextAutoPlay || (notification.userInfo?["skipAutoPlay"] as? Bool ?? false) {
                    skipAutoPlay = true
                } else {
                    skipAutoPlay = false
                }

                withAnimation(.easeInOut(duration: 0.3)) {
                    currentUserIndex = index
                }

                // If postIndex is specified, send ScrollToPost notification after user transition
                if let postIndex = notification.userInfo?["postIndex"] as? Int,
                   index < allUserPosts.count {
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
        }
        .onChange(of: currentDisplayedUserIndex) { newIndex in
            if currentUserIndex != newIndex {
                currentUserIndex = newIndex
            }
        }
        .onAppear {
            if !hasInitialized && !allUserPosts.isEmpty {
                currentDisplayedUserIndex = currentUserIndex
                hasInitialized = true
            } else if hasInitialized {
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
    let isInitialLoad: Bool
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
                        contextUserId: userPosts.user.id,
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
                        contextUserId: userPosts.user.id,
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
                        contextUserId: userPosts.user.id,
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

            if newValue {
                // Update radio button when this user becomes current
                NotificationCenter.default.post(
                    name: NSNotification.Name("UpdateCurrentPostIndex"),
                    object: nil,
                    userInfo: ["userId": userPosts.user.id, "postIndex": currentPostIndex]
                )

                if !skipAutoPlay && !isInitialLoad {
                    // Auto-play music when this user becomes current (but not on initial app launch)
                    Task {
                        await startPlaybackForCurrentPost()
                    }
                } else {
                }
            }
        }
        .onChange(of: currentPostIndex) { newIndex in
            // Update radio button when post index changes
            if isCurrent {
                NotificationCenter.default.post(
                    name: NSNotification.Name("UpdateCurrentPostIndex"),
                    object: nil,
                    userInfo: ["userId": userPosts.user.id, "postIndex": newIndex]
                )
            }
        }
        .onAppear {
            // Always update radio button on appear
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateCurrentPostIndex"),
                object: nil,
                userInfo: ["userId": userPosts.user.id, "postIndex": currentPostIndex]
            )

            // If this tab becomes current and there's already a song playing
            if isCurrent {
                if let currentlyPlayingPostId = playbackStateManager.currentlyPlayingPostId {
                    // Check if the currently playing post exists in this user's posts
                    if userPosts.posts.contains(where: { $0.id == currentlyPlayingPostId }) {
                        // Update the userId context to this tab
                        playbackStateManager.updatePlaybackContext(userId: userPosts.user.id)
                    }
                }
            }

            if isCurrent && !skipAutoPlay && !isInitialLoad {
                // Auto-play music when first displayed (but not on initial app launch)
                Task {
                    await startPlaybackForCurrentPost()
                }
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
            return
        }

        let post = userPosts.posts[currentPostIndex]
        let postId = post.id

        // Check if this post is already playing
        if playbackStateManager.currentlyPlayingPostId == postId {
            return
        }

        guard let previewUrl = post.previewUrl else {
            return
        }

        do {
            // Stop any currently playing post
            musicPlayer.stopPreview()

            // Small delay to ensure smooth transition
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            // Start playback for this post
            try await musicPlayer.playPreviewFromURL(previewUrl, startTime: post.startTime)
            await MainActor.run {
                playbackStateManager.startPlayback(for: postId, userId: userPosts.user.id)
            }

            // Auto-stop after duration
            let duration = post.endTime - post.startTime
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await MainActor.run {
                    if playbackStateManager.currentlyPlayingPostId == postId {
                        musicPlayer.stopPreview()
                        playbackStateManager.stopPlayback()
                    } else {
                    }
                }
            }
        } catch {
        }
    }
}

struct PostCardView: View {
    let post: Post
    let isCurrent: Bool
    @Binding var currentPostIndex: Int
    let expectedIndex: Int
    let contextUserId: Int64 // The userId of the UserPosts this post belongs to
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var playbackStateManager = PlaybackStateManager.shared
    @ObservedObject private var likeStateManager = LikeStateManager.shared
    @ObservedObject private var commentStateManager = CommentStateManager.shared
    private let musicPlayer = MusicKitManager.shared
    @State private var showingDeleteConfirmation = false
    @State private var showingBlockConfirmation = false
    @State private var showingComments = false
    @State private var showingReportCommentSheet = false
    @State private var commentToReport: Comment?
    @State private var showingReportPostSheet = false
    @State private var showingPostActions = false
    @State private var showingUserProfile = false
    @State private var showingAppleMusicConfirmation = false
    @State private var appleMusicUrlToOpen: URL?
    @State private var backgroundScale: CGFloat = 1.0
    @State private var backgroundRotation: Double = 0

    init(post: Post, isCurrent: Bool, currentPostIndex: Binding<Int>, expectedIndex: Int, contextUserId: Int64, onDelete: (() -> Void)? = nil) {
        self.post = post
        self.isCurrent = isCurrent
        self._currentPostIndex = currentPostIndex
        self.expectedIndex = expectedIndex
        self.contextUserId = contextUserId
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
                        // .rotationEffect(.degrees(backgroundRotation))
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
                        // .rotationEffect(.degrees(backgroundRotation))
                }
                .allowsHitTesting(false)
                .zIndex(1)
                .onChange(of: isPlaying) { playing in
                    if playing {
                        // 画面遷移アニメーション完了後に回転を開始
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            startBackgroundAnimation()
                        }
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
                        font: .system(size: DeviceType.isIPad ? 24 : 20, weight: .semibold),
                        color: .white,
                        frameWidth: albumSize
                    )
                    .frame(height: DeviceType.isIPad ? 36 : 30)
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
                                                .font(.system(size: DeviceType.isIPad ? 14 : 12))
                                                .foregroundColor(.white.opacity(0.6))
                                        )
                                }
                                .frame(width: DeviceType.isIPad ? 44 : 36, height: DeviceType.isIPad ? 44 : 36)
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

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .bottom, spacing: 2) {
                                        Text(APIClient.shared.currentUserId == post.user.id ? "あなた" : post.user.displayName)
                                            .font(.system(size: DeviceType.isIPad ? 16 : 14, weight: .semibold))
                                        Text("のおすすめ")
                                            .font(.system(size: DeviceType.isIPad ? 13 : 11))
                                    }
                                    .foregroundStyle(
                                        APIClient.shared.currentUserId == post.user.id ?
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.orange,
                                                Color.red
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ) :
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white,
                                                Color.white
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(timeAgoString(from: post.createdAt))
                                            .font(.system(size: DeviceType.isIPad ? 12 : 10))
                                            .foregroundColor(.white.opacity(0.6))
                                        Image(systemName: post.user.isPublic == true ? "network" : "network.badge.shield.half.filled")
                                            .font(.system(size: DeviceType.isIPad ? 12 : 10))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, DeviceType.isIPad ? 16 : 12)
                                .padding(.vertical, DeviceType.isIPad ? 8 : 6)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.5))
                                )
                                .onTapGesture {
                                    showingUserProfile = true
                                }

                                Spacer()
                            }
                            .padding(DeviceType.isIPad ? 16 : 12)
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
                                        .frame(width: DeviceType.isIPad ? 44 : 36, height: DeviceType.isIPad ? 44 : 36)
                                        .overlay(
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: DeviceType.isIPad ? 20 : 16, weight: .semibold))
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
                                            .frame(width: DeviceType.isIPad ? 72 : 60, height: DeviceType.isIPad ? 72 : 60)
                                            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)

                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: DeviceType.isIPad ? 28 : 24))
                                            .foregroundColor(.black)
                                            .offset(x: isPlaying ? 0 : 2)
                                    }
                                }

                                if isPlaying {
                                    WaveformView()
                                        .frame(width: DeviceType.isIPad ? 96 : 80, height: DeviceType.isIPad ? 60 : 50)
                                        .transition(.scale.combined(with: .opacity))
                                }

                                Spacer()
                            }
                            .padding(DeviceType.isIPad ? 20 : 16)
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
                                                .font(.system(size: DeviceType.isIPad ? 24 : 20))
                                                .foregroundColor(isLiked ? .red : .white)
                                            Text("\(likeCount)")
                                                .font(.system(size: DeviceType.isIPad ? 16 : 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, DeviceType.isIPad ? 16 : 12)
                                        .padding(.vertical, DeviceType.isIPad ? 10 : 8)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(20)
                                    }

                                    // Comment button
                                    Button(action: {
                                        showingComments = true
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "bubble.right")
                                                .font(.system(size: DeviceType.isIPad ? 24 : 20))
                                            Text("\(commentCount)")
                                                .font(.system(size: DeviceType.isIPad ? 16 : 14, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, DeviceType.isIPad ? 16 : 12)
                                        .padding(.vertical, DeviceType.isIPad ? 10 : 8)
                                        .background(Color.black.opacity(0.5))
                                        .cornerRadius(20)
                                    }
                                }
                                .padding(DeviceType.isIPad ? 20 : 16)
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
                    appleMusicUrlToOpen = url
                    showingAppleMusicConfirmation = true
                }
            }

            if let currentUserId = APIClient.shared.currentUserId, currentUserId == post.user.id {
                Button("削除", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } else {
                Button("ブロック", role: .destructive) {
                    showingBlockConfirmation = true
                }
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
        .alert("ユーザーをブロック", isPresented: $showingBlockConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("ブロック", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("\(post.user.displayName)をブロックしますか？ブロックすると、このユーザーの投稿が表示されなくなります。")
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
            .navigationViewStyle(.stack)
        }
        .alert("外部サイトへ移動", isPresented: $showingAppleMusicConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("移動する") {
                if let url = appleMusicUrlToOpen {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            if let url = appleMusicUrlToOpen {
                Text("Apple Musicに移動します。\n\n\(url.absoluteString)")
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

            // Update playback state on main actor - use contextUserId instead of post.user.id
            await MainActor.run {
                playbackStateManager.startPlayback(for: post.id, userId: contextUserId)
            }

            // Auto-stop after duration
            let duration = post.endTime - post.startTime
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await MainActor.run {
                    if playbackStateManager.currentlyPlayingPostId == post.id {
                        musicPlayer.stopPreview()
                        playbackStateManager.stopPlayback()
                    }
                }
            }
        } catch {
            // Silently fail
        }
    }

    private func togglePlayback() async {
        if isPlaying {
            musicPlayer.stopPreview()
            await MainActor.run {
                playbackStateManager.stopPlayback()
            }
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

    private func blockUser() async {
        do {
            try await APIClient.shared.blockUser(userId: post.user.id)
            print("🚫 Blocked user: \(post.user.id)")

            // Notify FeedView to remove this user's posts
            NotificationCenter.default.post(
                name: NSNotification.Name("UserBlocked"),
                object: nil,
                userInfo: ["blockedUserId": post.user.id]
            )
        } catch {
            print("❌ Failed to block user: \(error)")
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
                        .foregroundStyle(
                            APIClient.shared.currentUserId == comment.user.id ?
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.orange,
                                    Color.red
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.primary,
                                    Color.primary
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
        // Check if this user's tab is currently playing
        guard let currentlyPlayingId = playbackStateManager.currentlyPlayingPostId,
              let currentlyPlayingUserId = playbackStateManager.currentlyPlayingUserId else {
            return false
        }
        // Only show playing animation if the playing context matches this user
        return currentlyPlayingUserId == userPosts.user.id &&
               userPosts.posts.contains { $0.id == currentlyPlayingId }
    }

    var body: some View {
        VStack(spacing: 4) {
            // User name
            HStack(spacing: 2) {
                Text(APIClient.shared.currentUserId == userPosts.user.id ? "あなた" : userPosts.user.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        APIClient.shared.currentUserId == userPosts.user.id ?
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color.red
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.8)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
            }
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
                        // Show music.note.list icon (when others show profile)
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 54, height: 54)

                            Image(systemName: "music.note.list")
                                .font(.system(size: 24))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.orange,
                                            Color.red
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
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

                // Border with gradient - orange when playing, white otherwise
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: isPlaying ? [
                                Color.orange.opacity(0.9),
                                Color.red.opacity(0.7)
                            ] : [
                                Color.white.opacity(0.6),
                                Color.white.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isPlaying ? 3 : 2
                    )
                    .frame(width: 54, height: 54)

                // Waveform animation when playing (inside the circle)
                if isPlaying {
                    MiniWaveformView()
                        .frame(width: 36, height: 24)
                        .transition(.opacity)
                }

                // Unread badge - show "NEW" text
                if unreadCount > 0 || (hasUnreadPosts && unreadCount == 0) {
                    VStack {
                        HStack {
                            Spacer()
                            Text("NEW")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.orange,
                                            Color.red
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                                .modifier(PulseAnimation())
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

// Helper function to format time ago
private func timeAgoString(from date: Date) -> String {
    let now = Date()
    let timeInterval = now.timeIntervalSince(date)

    let seconds = Int(timeInterval)
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24
    let weeks = days / 7

    if seconds < 60 {
        return "たった今"
    } else if minutes < 60 {
        return "\(minutes)分前"
    } else if hours < 24 {
        return "\(hours)時間前"
    } else if days < 7 {
        return "\(days)日前"
    } else if weeks < 4 {
        return "\(weeks)週間前"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

// Swipe hint view with animated arrows
struct SwipeHintView: View {
    @Binding var showSwipeHint: Bool
    @State private var animationOffset: CGFloat = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 16) {
                // Arrow grid (3 rows)
                VStack(spacing: 8) {
                    // First row: up arrow (centered)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 24, weight: .bold))

                    // Second row: left and right arrows with space in center
                    HStack(spacing: 32) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 24, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 24, weight: .bold))
                    }

                    // Third row: down arrow (centered)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 24, weight: .bold))
                }
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange,
                            Color.red
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // Text
                Text("上下左右のスライドで\n投稿を切り替えよう！")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color.red
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange.opacity(0.8),
                                        Color.red.opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
            )

            // Close button (top-left)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSwipeHint = false
                }
            }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(8)
        }
        .offset(y: animationOffset)
        .opacity(opacity)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                animationOffset = -10
            }
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                opacity = 0.7
            }
        }
    }
}
