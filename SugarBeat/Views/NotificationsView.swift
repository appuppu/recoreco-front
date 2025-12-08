import SwiftUI

struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                            NotificationRow(notification: notification) {
                                Task {
                                    await viewModel.deleteNotification(notificationId: notification.id)
                                }

                                if notification.type == "LIKE" || notification.type == "COMMENT" {
                                    if let postId = notification.postId {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            NotificationCenter.default.post(
                                                name: NSNotification.Name("PlayPostInMyProfile"),
                                                object: nil,
                                                userInfo: ["postId": postId]
                                            )
                                        }
                                    }
                                } else {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        NotificationCenter.default.post(
                                            name: NSNotification.Name("ShowUserProfile"),
                                            object: nil,
                                            userInfo: ["userId": notification.sender.id]
                                        )
                                    }
                                }
                            }

                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
            }
        }
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

struct NotificationRow: View {
    let notification: Notification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: imageUrl)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: isPostNotification ? 8 : 25)
                        .fill(Color.white.opacity(0.3))
                        .overlay(
                            Image(systemName: isPostNotification ? "music.note" : "person.fill")
                                .foregroundColor(.white.opacity(0.6))
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: isPostNotification ? 8 : 25))

                VStack(alignment: .leading, spacing: 4) {
                    Text(notificationText)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

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
        }
    }

    private var isPostNotification: Bool {
        notification.type == "LIKE" || notification.type == "COMMENT"
    }

    private var imageUrl: String {
        if isPostNotification, let artworkUrl = notification.artworkUrl {
            return artworkUrl
        }
        return APIClient.shared.getFullImageURL(notification.sender.profileImageUrl) ?? ""
    }

    private var notificationText: String {
        let displayName = notification.sender.displayName
        switch notification.type {
        case "FOLLOW":
            return "\(displayName)さんにフォローされました"
        case "LIKE":
            return "\(displayName)さんがあなたの紹介にいいねしました"
        case "COMMENT":
            return "\(displayName)さんがあなたの紹介にコメントしました"
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

    func deleteNotification(notificationId: Int64) async {
        do {
            try await APIClient.shared.deleteNotification(notificationId: notificationId)
            notifications.removeAll { $0.id == notificationId }
            NotificationCenter.default.post(name: NSNotification.Name("RefreshNotificationBadge"), object: nil)
        } catch {
            errorMessage = "Failed to delete notification: \(error.localizedDescription)"
        }
    }

    func deleteAllNotifications() async {
        do {
            try await APIClient.shared.deleteAllNotifications()
            notifications.removeAll()
            NotificationCenter.default.post(name: NSNotification.Name("RefreshNotificationBadge"), object: nil)
        } catch {
            errorMessage = "Failed to delete all notifications: \(error.localizedDescription)"
        }
    }
}
