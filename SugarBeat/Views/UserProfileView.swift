import SwiftUI
import FirebaseAuth

/// ユーザープロフィール画面 - グリッドレイアウト + 左上にユーザー情報オーバーレイ
struct UserProfileView: View {
    let userId: String
    @StateObject private var viewModel = UserProfileViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false
    @State private var showingProfileEdit = false
    @State private var viewMode: ViewMode = .posts
    @State private var showingUserMenu = false

    enum ViewMode {
        case posts
        case sharedChannels
        case personalChannels
    }

    var isOwnProfile: Bool {
        Auth.auth().currentUser?.uid == userId
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea(edges: .bottom)

                if viewModel.isLoading && viewModel.user == nil && !viewModel.isBlocked && !viewModel.isBlockedBy {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.isBlocked {
                    // ブロック状態（操作ユーザーがブロックしている）
                    blockedViewWithClose
                } else if viewModel.isBlockedBy {
                    // ブロックされている状態（操作ユーザーがブロックされている）
                    blockedByViewWithClose
                } else if let user = viewModel.user {
                    if canViewPosts(user: user) {
                        VStack(spacing: 0) {
                            // ユーザー情報ヘッダー
                            userInfoHeader(user: user)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 12)

                            // コンテンツ
                            if viewMode == .posts {
                                if viewModel.posts.isEmpty {
                                    emptyPostsView
                                } else {
                                    PostGridView(
                                        posts: viewModel.posts,
                                        showingLoginPrompt: $showingLoginPrompt,
                                        showUserInfo: false,
                                        isLoading: viewModel.isLoading,
                                        isLoadingMore: viewModel.isLoadingMore,
                                        onRefresh: {
                                            await viewModel.loadUser(userId: userId)
                                        },
                                        onLoadMore: {
                                            await viewModel.loadMorePosts(userId: userId)
                                        }
                                    )
                                }
                            } else if viewMode == .sharedChannels {
                                channelsListView(channelType: .shared)
                            } else {
                                channelsListView(channelType: .personal)
                            }
                        }
                    } else {
                        privateAccountView(user: user)
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red.opacity(0.7))
                        Text(errorMessage)
                            .foregroundColor(.white.opacity(0.7))
                        Button("再読み込み") {
                            Task {
                                await viewModel.loadUser(userId: userId)
                            }
                        }
                        .foregroundColor(.purple)
                    }
                }
            }
            .navigationBarHidden(true)
            .presentationDragIndicator(.visible)
        }
        .alert("ログインが必要です", isPresented: $showingLoginPrompt) {
            Button("はい") {
                showingLoginSheet = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この機能を使用するにはログインが必要です")
        }
        .fullScreenCover(isPresented: $showingLoginSheet) {
            if #available(iOS 16.4, *) {
                LoginView()
                    .presentationBackground(Color.black)
                    .presentationCornerRadius(20)
            } else {
                LoginView()
            }
        }
        .sheet(isPresented: $showingProfileEdit) {
            if let currentUser = authManager.currentUser {
                if #available(iOS 16.4, *) {
                    ProfileEditView(currentUser: currentUser)
                        .presentationBackground(Color.black)
                        .presentationCornerRadius(20)
                } else {
                    ProfileEditView(currentUser: currentUser)
                }
            }
        }
        .confirmationDialog("ユーザーオプション", isPresented: $showingUserMenu, titleVisibility: .hidden) {
            Button("ユーザーをブロック", role: .destructive) {
                Task {
                    await viewModel.blockUser(userId: userId)
                    dismiss()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .task {
            await viewModel.loadUser(userId: userId)
        }
    }

    // MARK: - User Info Header
    @ViewBuilder
    private func userInfoHeader(user: User) -> some View {
        VStack(spacing: 12) {
            // バツボタンとメニューボタン
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()

                // 他のユーザーの場合のみメニューボタンを表示
                if !isOwnProfile {
                    Button(action: { showingUserMenu = true }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                }
            }

            HStack(spacing: 12) {
                // プロフィール画像
                AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()
            }

            // 切り替えボタン
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation {
                        viewMode = .posts
                    }
                }) {
                    Text("投稿")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewMode == .posts ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewMode == .posts ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(8)
                }

                Button(action: {
                    withAnimation {
                        viewMode = .sharedChannels
                    }
                    if viewModel.channels.isEmpty {
                        Task {
                            await viewModel.loadChannels(userId: userId)
                        }
                    }
                }) {
                    Text("参加中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewMode == .sharedChannels ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewMode == .sharedChannels ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(8)
                }

                Button(action: {
                    withAnimation {
                        viewMode = .personalChannels
                    }
                    if viewModel.channels.isEmpty {
                        Task {
                            await viewModel.loadChannels(userId: userId)
                        }
                    }
                }) {
                    Text("個人")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewMode == .personalChannels ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(viewMode == .personalChannels ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Helper Views
    private var blockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.4))
            Text("ブロック中のユーザーです")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var blockedViewWithClose: some View {
        VStack {
            // 閉じるボタン
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 60)
                .padding(.leading, 12)
                Spacer()
            }

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.4))
                Text("ブロック中です")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
    }

    private var blockedByViewWithClose: some View {
        VStack {
            // 閉じるボタン
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 60)
                .padding(.leading, 12)
                Spacer()
            }

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.4))
                Text("ユーザーが見つかりませんでした。")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
    }

    private var emptyPostsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.4))
            Text("紹介がありません")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func privateAccountView(user: User) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.4))
            Text("フォローして紹介を見る")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func canViewPosts(user: User) -> Bool {
        // 全てのユーザーの投稿を閲覧可能（パブリック）
        return true
    }

    @ViewBuilder
    private func channelsListView(channelType: ChannelType) -> some View {
        // For personal channels, only show channels owned by this user
        // For shared channels, show all channels they're part of
        let filteredChannels = viewModel.channels.filter { channel in
            if channelType == .personal {
                // 個人チャンネル: このユーザーが所有しているもののみ
                let isOwned = channel.userId == userId
                print("🔍 [UserProfileView] Personal channel filter: \(channel.name) | userId: \(channel.userId) | profileUserId: \(userId) | isOwned: \(isOwned)")
                return channel.channelType == channelType && isOwned
            } else {
                // 共有チャンネル: このユーザーが参加しているもの全て
                return channel.channelType == channelType
            }
        }

        if filteredChannels.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.4))
                Text(channelType == .shared ? "参加中の公開チャンネルはありません" : "個人チャンネルがありません")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredChannels) { channel in
                        if let channelId = channel.id {
                            NavigationLink(destination: ChannelDetailView(channelId: channelId)) {
                                ChannelRowView(channel: channel)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            ChannelRowView(channel: channel)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
    }
}

struct ChannelRowView: View {
    let channel: Channel
    var isEditable: Bool = false
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // アルバムアート
            if let artworkUrl = channel.latestPostArtworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Channel type icon
                    Image(systemName: channel.channelType == .shared ? "globe" : "person.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Text(channel.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    if channel.channelType == .shared {
                        Text("\(channel.followerCount ?? 0)人が参加")
                            .font(.caption)
                    } else {
                        Text("\(channel.followerCount ?? 0)人がフォロー")
                            .font(.caption)
                    }
                }
                .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // 編集ボタン（自分のチャンネルの場合のみ）
            if isEditable, let onEdit = onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

