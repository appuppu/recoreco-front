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
    @State private var showingUserMenu = false
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

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
                        ZStack(alignment: .top) {
                            // コンテンツ
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
                                    },
                                    onScrollOffsetChange: { offset in
                                        scrollOffset = offset
                                        print("📊 [UserProfile] Scroll offset: \(offset), headerHeight: \(headerHeight)")
                                    },
                                    topPadding: headerHeight,
                                    scrollResetTrigger: 0 // 使用しない
                                )
                                .id("posts-grid") // 投稿タブのときは固定のID
                            }

                            // ユーザー情報ヘッダー (オーバーレイ)
                            VStack(spacing: 0) {
                                userInfoHeader(user: user)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    .padding(.bottom, 12)
                                    .background(Color.black)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .onAppear {
                                                    headerHeight = geo.size.height
                                                    print("🔍 [UserProfile] Header height measured: \(headerHeight)")
                                                }
                                                .onChange(of: geo.size) { newSize in
                                                    headerHeight = newSize.height
                                                    print("🔍 [UserProfile] Header height changed: \(headerHeight)")
                                                }
                                        }
                                    )

                                Spacer()
                            }
                            .offset(y: {
                                let offsetY = !viewModel.posts.isEmpty ? -min(scrollOffset, headerHeight) : 0
                                if !viewModel.posts.isEmpty {
                                    print("📍 [UserProfile Header] offset calculation - scrollOffset: \(scrollOffset), headerHeight: \(headerHeight), resulting offsetY: \(offsetY)")
                                }
                                return offsetY
                            }())
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

            // 上段: アイコン + ユーザー名 / bio
            HStack(alignment: .top, spacing: 12) {
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
                        .lineLimit(1)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 中段: フォロー中 / フォロワー数（独立した行・幅を均等分割）
            if let userId = user.id {
                HStack(spacing: 0) {
                    NavigationLink(destination: FollowListView(userId: userId, listType: .following)) {
                        countItem(count: user.followingCount ?? 0, label: "フォロー中")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .frame(height: 24)
                        .overlay(Color.white.opacity(0.2))

                    NavigationLink(destination: FollowListView(userId: userId, listType: .followers)) {
                        countItem(count: user.followerCount ?? 0, label: "フォロワー")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // 下段: フォローボタン（自分以外）
            if !isOwnProfile, let userId = user.id {
                FollowButton(userId: userId, onChange: { _ in
                    Task { await viewModel.loadUser(userId: userId) }
                })
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func countItem(count: Int, label: String) -> some View {
        // 数字とラベルを横1行で表示。文字数で崩れないよう lineLimit(1) + fixedSize。
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .lineLimit(1)
        .fixedSize()
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

}

// MARK: - UserProfileHeaderHeightPreferenceKey
struct UserProfileHeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

