import SwiftUI
import FirebaseAuth

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            } else if viewModel.notifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("通知はありません")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.notifications) { notification in
                            NotificationNavigationWrapper(
                                notification: notification,
                                onDelete: {
                                    Task {
                                        if let notificationId = notification.id {
                                            await viewModel.deleteNotification(notificationId: notificationId)
                                        }
                                    }
                                }
                            )

                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await viewModel.loadNotifications()
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar {
            if !viewModel.notifications.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("すべて削除") {
                        Task {
                            await viewModel.deleteAllNotifications()
                        }
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .task {
            await viewModel.loadNotifications()
        }
    }
}

// Navigation wrapper for different notification types
struct NotificationNavigationWrapper: View {
    let notification: Notification
    let onDelete: () -> Void

    var body: some View {
        Group {
            switch notification.type {
            case .like:
                // Navigate to post detail
                if let postId = notification.postId {
                    NavigationLink {
                        SinglePostView(postId: postId, showCommentsOnAppear: false)
                            .task {
                                markAsRead()
                            }
                    } label: {
                        NotificationRow(notification: notification)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    NotificationRow(notification: notification)
                }

            case .comment:
                // Navigate to post detail and show comments
                if let postId = notification.postId {
                    NavigationLink {
                        SinglePostView(postId: postId, showCommentsOnAppear: true)
                            .task {
                                markAsRead()
                            }
                    } label: {
                        NotificationRow(notification: notification)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    NotificationRow(notification: notification)
                }

            case .channelFollow:
                // Navigate to user profile
                NavigationLink {
                    UserProfileView(userId: notification.senderId)
                        .task {
                            markAsRead()
                        }
                } label: {
                    NotificationRow(notification: notification)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func markAsRead() {
        guard !notification.isRead, let notificationId = notification.id else { return }
        Task {
            try? await FirestoreNotificationManager.shared.markAsRead(notificationId: notificationId)
            NotificationCenter.default.post(name: NSNotification.Name("ReloadUnreadCounts"), object: nil)
        }
    }
}

// Single post view for showing a single post from notification
struct SinglePostView: View {
    let postId: String
    var showCommentsOnAppear: Bool = false
    @StateObject private var viewModel = SinglePostViewModel()
    @State private var showingLoginPrompt = false
    @State private var showingComments = false
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            } else if let post = viewModel.post {
                PostGridView(
                    posts: [post],
                    showingLoginPrompt: $showingLoginPrompt,
                    showUserInfo: true,
                    respectNavigationBar: true
                )
                .environmentObject(authManager)
                .sheet(isPresented: $showingComments) {
                    if let post = viewModel.post {
                        NavigationView {
                            CommentsView(post: post)
                                .environmentObject(authManager)
                        }
                    }
                }
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red.opacity(0.7))
                    Text(errorMessage)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("投稿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadPost(postId: postId)
            // 投稿読み込み後、コメント通知の場合はコメントシートを開く
            if showCommentsOnAppear, viewModel.post != nil {
                // 少し遅延を入れて、ビューが完全に表示されてからシートを開く
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
                showingComments = true
            }
        }
        .fullScreenCover(isPresented: $showingLoginPrompt) {
            LoginView()
        }
    }
}

@MainActor
class SinglePostViewModel: ObservableObject {
    @Published var post: Post?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadPost(postId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            post = try await FirestorePostManager.shared.getPost(postId: postId)

            // Initialize like and comment states
            if let post = post, let postId = post.id {
                LikeStateManager.shared.updateFromServer(
                    postId: postId,
                    isLiked: post.isLiked ?? false,
                    count: post.likeCount ?? 0
                )
                CommentStateManager.shared.initialize(postId: postId, count: post.commentCount)
            }
        } catch {
            errorMessage = "投稿の読み込みに失敗しました"
        }

        isLoading = false
    }
}

struct NotificationRow: View {
    let notification: Notification
    @State private var channelName: String?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: imageUrl)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                if isPostNotification {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.3))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.6))
                        )
                } else {
                    Image("recoreco")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: isPostNotification ? 8 : 25))

            VStack(alignment: .leading, spacing: 4) {
                if notification.type == .channelFollow, let name = channelName ?? notification.channelName {
                    // フォロー通知の場合、3行に分けて表示
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(notification.senderDisplayName)さんが")
                            .font(.system(size: 15))
                            .foregroundColor(.white)

                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.purple, Color.blue]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text("を")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }

                        Text(notification.channelType == "shared" ? "参加しました" : "フォローしました")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(notificationText)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(timeAgoString(from: notification.createdAt))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            if !notification.isRead {
                Text("NEW")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }

            Image(systemName: notificationIcon)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(notification.isRead ? Color.clear : Color.white.opacity(0.05))
        .task {
            // Load channel name if this is a channel follow notification
            if notification.type == .channelFollow && notification.channelName == nil,
               let channelId = notification.postId {
                if let channel = try? await FirestoreChannelManager.shared.getChannel(channelId: channelId) {
                    channelName = channel.name
                }
            }
        }
    }

    private var isPostNotification: Bool {
        notification.type == .like || notification.type == .comment
    }

    private var imageUrl: String {
        if isPostNotification, let artworkUrl = notification.artworkUrl {
            return artworkUrl
        }
        return notification.senderProfileImageUrl ?? ""
    }

    private var notificationText: String {
        let displayName = notification.senderDisplayName
        switch notification.type {
        case .like:
            return "\(displayName)さんがあなたの投稿にいいねしました"
        case .comment:
            return "\(displayName)さんがあなたの投稿にコメントしました"
        case .channelFollow:
            let actionText = notification.channelType == "shared" ? "参加しました" : "フォローしました"
            // Use loaded channel name first, then notification's channel name, then fallback
            if let name = channelName ?? notification.channelName {
                return "\(displayName)さんが\(name)を\(actionText)"
            } else {
                return "\(displayName)さんがあなたのチャンネルを\(actionText)"
            }
        }
    }

    private var notificationIcon: String {
        switch notification.type {
        case .like:
            return "heart.fill"
        case .comment:
            return "bubble.right.fill"
        case .channelFollow:
            return "music.note.house.fill"
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
        } else if seconds < 2592000 {
            return "\(Int(seconds / 86400))日前"
        } else {
            return "\(Int(seconds / 2592000))ヶ月前"
        }
    }
}

@MainActor
class NotificationsViewModel: ObservableObject {
    @Published var notifications: [Notification] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadNotifications() async {
        isLoading = true
        errorMessage = nil

        do {
            let (fetchedNotifications, _) = try await FirestoreNotificationManager.shared.getCurrentUserNotifications()
            notifications = fetchedNotifications
        } catch {
            errorMessage = "Failed to load notifications: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func deleteNotification(notificationId: String) async {
        do {
            try await FirestoreNotificationManager.shared.deleteNotification(notificationId: notificationId)
            notifications.removeAll { $0.id == notificationId }
            NotificationCenter.default.post(name: NSNotification.Name("ReloadUnreadCounts"), object: nil)
        } catch {
            errorMessage = "Failed to delete notification: \(error.localizedDescription)"
        }
    }

    func deleteAllNotifications() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        do {
            try await FirestoreNotificationManager.shared.deleteAllNotifications(userId: currentUserId)
            notifications.removeAll()
            NotificationCenter.default.post(name: NSNotification.Name("ReloadUnreadCounts"), object: nil)
        } catch {
            errorMessage = "Failed to delete all notifications: \(error.localizedDescription)"
        }
    }
}
