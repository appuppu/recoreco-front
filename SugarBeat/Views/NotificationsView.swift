import SwiftUI

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUserId: Int64?
    @State private var showingUserProfile = false
    @State private var selectedPostId: Int64?

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.notifications.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.5))
                            Text("通知はありません")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.notifications) { notification in
                                    NotificationRow(notification: notification) {
                                        // Mark as read
                                        Task {
                                            await viewModel.markAsRead(notificationId: notification.id)
                                        }

                                        // Handle different notification types
                                        if notification.type == "LIKE" || notification.type == "COMMENT" {
                                            // For LIKE and COMMENT, navigate to post
                                            if let postId = notification.postId {
                                                // Close notifications view
                                                dismiss()

                                                // Post notification to navigate to the post
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    NotificationCenter.default.post(
                                                        name: NSNotification.Name("NavigateToPost"),
                                                        object: nil,
                                                        userInfo: ["postId": postId, "senderId": notification.sender.id]
                                                    )
                                                }
                                            }
                                        } else {
                                            // For FOLLOW, show user profile
                                            selectedUserId = notification.sender.id
                                            showingUserProfile = true
                                        }
                                    }

                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                if !viewModel.notifications.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("すべて既読") {
                            Task {
                                await viewModel.markAllAsRead()
                            }
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .task {
            await viewModel.loadNotifications()
        }
        .sheet(isPresented: $showingUserProfile) {
            if let userId = selectedUserId {
                NavigationView {
                    UserProfileView(userId: userId)
                }
            }
        }
    }
}

struct NotificationRow: View {
    let notification: Notification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile image
                AsyncImage(url: URL(string: notification.sender.profileImageUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.6))
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    // Notification text
                    Text(notificationText)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Time
                    Text(timeAgoString(from: notification.createdAt))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Unread indicator
                if !notification.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                }

                // Icon based on type
                Image(systemName: notificationIcon)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(notification.isRead ? Color.clear : Color.white.opacity(0.05))
        }
    }

    private var notificationText: String {
        let displayName = notification.sender.displayName
        switch notification.type {
        case "FOLLOW":
            return "\(displayName)さんにフォローされました"
        case "LIKE":
            return "\(displayName)さんがあなたの投稿にいいねしました"
        case "COMMENT":
            return "\(displayName)さんがあなたの投稿にコメントしました"
        default:
            return "\(displayName)さんから通知があります"
        }
    }

    private var notificationIcon: String {
        switch notification.type {
        case "FOLLOW":
            return "person.badge.plus"
        case "LIKE":
            return "heart.fill"
        case "COMMENT":
            return "bubble.right.fill"
        default:
            return "bell.fill"
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
            notifications = try await APIClient.shared.getNotifications()
        } catch {
            errorMessage = "Failed to load notifications: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func markAsRead(notificationId: Int64) async {
        do {
            try await APIClient.shared.markNotificationAsRead(notificationId: notificationId)

            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index] = Notification(
                    id: notifications[index].id,
                    sender: notifications[index].sender,
                    type: notifications[index].type,
                    postId: notifications[index].postId,
                    isRead: true,
                    createdAt: notifications[index].createdAt
                )
            }
        } catch {
            errorMessage = "Failed to mark notification as read: \(error.localizedDescription)"
        }
    }

    func markAllAsRead() async {
        do {
            try await APIClient.shared.markAllNotificationsAsRead()

            // Update local state
            notifications = notifications.map { notification in
                Notification(
                    id: notification.id,
                    sender: notification.sender,
                    type: notification.type,
                    postId: notification.postId,
                    isRead: true,
                    createdAt: notification.createdAt
                )
            }
        } catch {
            errorMessage = "Failed to mark all notifications as read: \(error.localizedDescription)"
        }
    }
}
