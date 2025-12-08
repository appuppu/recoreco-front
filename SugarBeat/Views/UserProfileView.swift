import SwiftUI

/// ユーザープロフィール画面 - グリッドレイアウト + 左上にユーザー情報オーバーレイ
struct UserProfileView: View {
    let userId: Int64
    @StateObject private var viewModel = UserProfileViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingLoginPrompt = false
    @State private var showingLoginSheet = false
    @State private var showingFollowList = false
    @State private var followListType: FollowListType = .following
    @State private var showingProfileEdit = false

    var isOwnProfile: Bool {
        APIClient.shared.currentUserId == userId
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.user == nil && !viewModel.isBlocked {
                ProgressView()
                    .tint(.white)
            } else if viewModel.isBlocked {
                // ブロック状態（ユーザー情報がなくても表示）
                blockedViewWithClose
            } else if let user = viewModel.user {
                if canViewPosts(user: user) {
                    if viewModel.posts.isEmpty {
                        emptyPostsView
                    } else {
                        // PostGridViewを使用 + ユーザー情報オーバーレイ
                        ZStack(alignment: .topLeading) {
                            PostGridView(
                                posts: viewModel.posts,
                                showingLoginPrompt: $showingLoginPrompt,
                                showUserInfo: false,
                                isLoading: viewModel.isLoading,
                                onRefresh: {
                                    await viewModel.loadUser(userId: userId)
                                }
                            )

                            // 左上のユーザー情報オーバーレイ
                            userInfoOverlay(user: user)
                                .padding(.top, 12)
                                .padding(.leading, 12)
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
        .alert("ログインが必要です", isPresented: $showingLoginPrompt) {
            Button("はい") {
                showingLoginSheet = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この機能を使用するにはログインが必要です")
        }
        .sheet(isPresented: $showingLoginSheet) {
            LoginView()
        }
        .sheet(isPresented: $showingFollowList) {
            NavigationStack {
                FollowListView(userId: userId, listType: followListType)
            }
        }
        .sheet(isPresented: $showingProfileEdit) {
            if let authUser = authManager.currentUser {
                let user = User(
                    id: authUser.userId,
                    username: authUser.username,
                    email: authUser.email,
                    displayName: authUser.displayName,
                    profileImageUrl: authUser.profileImageUrl,
                    bio: nil,
                    isPublic: authUser.isPublic,
                    createdAt: nil,
                    isFollowing: nil,
                    isFollower: nil,
                    isMutual: nil,
                    followingCount: nil,
                    followerCount: nil
                )
                ProfileEditView(currentUser: user)
            }
        }
        .task {
            await viewModel.loadUser(userId: userId)
        }
    }

    // MARK: - User Info Overlay
    @ViewBuilder
    private func userInfoOverlay(user: User) -> some View {
        let imageUrl = APIClient.shared.getFullImageURL(user.profileImageUrl)

        VStack(alignment: .leading, spacing: 10) {
            // バツボタン + プロフィール画像 + 名前
            HStack(spacing: 8) {
                // バツボタン
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.8))
                }

                // プロフィール画像
                AsyncImage(url: URL(string: imageUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    // 公開/非公開アイコン + 名前 + 設定ボタン（自分の場合）
                    HStack(spacing: 4) {
                        Image(systemName: user.isPublic == true ? "network" : "network.badge.shield.half.filled")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                        Text(user.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)

                        // 自分のプロフィールの場合は設定ボタンを表示
                        if isOwnProfile {
                            Button(action: { showingProfileEdit = true }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }

            // フォロー数・フォロワー数（タップ可能、大きめ表示）
            HStack(spacing: 16) {
                Button(action: {
                    showingFollowList = true
                    followListType = .following
                }) {
                    HStack(spacing: 4) {
                        Text("\(user.followingCount ?? 0)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("フォロー")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Button(action: {
                    showingFollowList = true
                    followListType = .followers
                }) {
                    HStack(spacing: 4) {
                        Text("\(user.followerCount ?? 0)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("フォロワー")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }

            // フォローボタン（自分以外の場合）
            if let currentUserId = APIClient.shared.currentUserId, currentUserId != user.id {
                if let isFollowing = user.isFollowing {
                    Button(action: {
                        Task {
                            if isFollowing {
                                await viewModel.unfollowUser(userId: userId)
                            } else {
                                await viewModel.followUser(userId: userId)
                            }
                        }
                    }) {
                        Text(isFollowing ? "フォロー中" : "フォロー")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Group {
                                    if isFollowing {
                                        Color.white.opacity(0.3)
                                    } else {
                                        AppTheme.horizontalGradient
                                    }
                                }
                            )
                            .cornerRadius(14)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
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
                .padding(.top, 12)
                .padding(.leading, 12)
                Spacer()
            }

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.4))
                Text("このユーザーは表示できません")
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
    }

    @ViewBuilder
    private func privateAccountView(user: User) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.4))
            Text(user.isPublic == true ? "フォローして紹介を見る" : "相互フォローで紹介を見ることができます")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func canViewPosts(user: User) -> Bool {
        (APIClient.shared.currentUserId == user.id) ||
        (user.isPublic == true) ||
        (user.isPublic != true && (user.isMutual ?? false))
    }
}
