import SwiftUI
import MusicKit

struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = CreatePostViewModel()
    @FocusState private var isCommentFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @Binding var postCreated: Bool
    @State private var selectedChannelType: ChannelType = .shared
    @State private var showingChannelPostSheet = false
    @State private var selectedChannelForPost: Channel?

    private var filteredChannels: [Channel] {
        viewModel.postableChannels.filter { $0.channelType == selectedChannelType }
    }

    @ViewBuilder
    private var channelListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Channel type switcher
                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation {
                            selectedChannelType = .shared
                        }
                    }) {
                        Text("参加中の公開チャンネル")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedChannelType == .shared ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedChannelType == .shared ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }

                    Button(action: {
                        withAnimation {
                            selectedChannelType = .personal
                        }
                    }) {
                        Text("個人チャンネル")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedChannelType == .personal ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedChannelType == .personal ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Channels list
                if viewModel.isLoadingChannels {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if filteredChannels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.house")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.4))
                        Text(selectedChannelType == .shared ? "参加中の公開チャンネルはありません" : "個人チャンネルがありません")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredChannels) { channel in
                            Button(action: {
                                selectedChannelForPost = channel
                                showingChannelPostSheet = true
                            }) {
                                ChannelRowViewForCreatePost(channel: channel)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 100)
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 12) {
            // Title
            Text("投稿")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.top)
                .onAppear {
                    print("🎵 [CreatePostView in CreatePostView.swift] Title '投稿' displayed")
                }

            // Music search bar
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.8))
                    TextField("", text: $viewModel.searchQuery, prompt: Text("曲名、アーティスト名で検索").foregroundColor(.white))
                        .foregroundColor(.white)
                        .tint(.white)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isSearchFocused)
                        .accentColor(.white)
                        .onSubmit {
                            Task {
                                await viewModel.performSearch()
                            }
                        }
                    if !viewModel.searchQuery.isEmpty {
                        Button(action: { viewModel.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)

                // 検索ボタン
                Button(action: {
                    isSearchFocused = false
                    Task {
                        await viewModel.performSearch()
                    }
                }) {
                    Text("検索")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
                .disabled(viewModel.searchQuery.isEmpty || viewModel.isSearching)
            }
            .padding(.horizontal)
        }
        .background(Color.clear)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var contentAreaView: some View {
        if viewModel.isSearching {
            VStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.searchResults.isEmpty {
            searchResultsView
        } else if viewModel.selectedSong != nil {
            selectedSongView
        } else {
            channelListView
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.searchResults, id: \.id) { song in
                    Button(action: {
                        Task {
                            await viewModel.selectSong(song)
                        }
                    }) {
                        MusicKitSearchRow(song: song)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var selectedSongView: some View {
        if let selectedSong = viewModel.selectedSong {
            ScrollView {
                VStack(spacing: 16) {
                    // Album artwork and song info
                    HStack(spacing: 12) {
                        if let artwork = selectedSong.artwork {
                            AsyncImage(url: artwork.url(width: 80, height: 80)) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 80)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                case .failure:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 80)
                                @unknown default:
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 80)
                                }
                            }
                            .frame(width: 80, height: 80)
                            .cornerRadius(8)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedSong.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Text(selectedSong.artistName)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Preview loading indicator
                    if viewModel.isFetchingPreview {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("プレビューを取得中...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.vertical, 8)
                    }

                    // Play/Stop button
                    Button(action: {
                        if viewModel.isPlaying {
                            viewModel.stopPreview()
                        } else {
                            Task {
                                await viewModel.playPreview()
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 20))
                            Text(viewModel.isPlaying ? "停止" : "30秒プレビュー再生")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: viewModel.isPlaying ?
                                    [Color.red, Color.orange] :
                                    [Color.green, Color.blue]
                                ),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isFetchingPreview)
                    .opacity(viewModel.isFetchingPreview ? 0.5 : 1.0)
                    .padding(.horizontal)

                    // Comment field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("コメント")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )

                            if viewModel.comment.isEmpty {
                                Text("最低一文字必要です")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 16)
                            }

                            TextEditor(text: $viewModel.comment)
                                .frame(height: 80)
                                .padding(8)
                                .background(Color.clear)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .focused($isCommentFocused)
                                .scrollContentBackground(.hidden)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("完了") {
                                            isCommentFocused = false
                                        }
                                    }
                                }
                        }
                        .frame(height: 80)
                    }
                    .padding(.horizontal)

                    // Channel selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("投稿先チャンネル")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        if viewModel.isLoadingChannels {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                            }
                            .padding()
                        } else if viewModel.channels.isEmpty {
                            VStack(spacing: 12) {
                                Text("まだチャンネルがありません")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                Button(action: {
                                    // Validate comment before opening channel creation sheet
                                    if viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        viewModel.errorMessage = "コメントを入力してください"
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            viewModel.errorMessage = nil
                                        }
                                    } else {
                                        viewModel.showingCreateChannelSheet = true
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("新しいチャンネルを作成")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(10)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.3))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        } else {
                            VStack(spacing: 12) {
                                // Channel picker - only show channels user can post to
                                Menu {
                                    ForEach(viewModel.postableChannels) { channel in
                                        Button(action: {
                                            viewModel.selectedChannel = channel
                                        }) {
                                            HStack {
                                                // Channel type icon
                                                Image(systemName: channel.channelType == .shared ? "globe" : "person.circle.fill")
                                                    .font(.caption)
                                                Text(channel.name)
                                                if viewModel.selectedChannel?.id == channel.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(viewModel.selectedChannel?.name ?? "チャンネルを選択")
                                            .foregroundColor(.white)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.black.opacity(0.4))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                }

                                // Create new channel button
                                Button(action: {
                                    // Validate comment before opening channel creation sheet
                                    if viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        viewModel.errorMessage = "コメントを入力してください"
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            viewModel.errorMessage = nil
                                        }
                                    } else {
                                        viewModel.showingCreateChannelSheet = true
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle")
                                        Text("新しいチャンネルを作成")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Post button
                    Button(action: {
                        // キーボードを閉じる
                        isCommentFocused = false
                        isSearchFocused = false

                        Task {
                            await viewModel.createPost()
                            if viewModel.postCreated {
                                postCreated = true
                                dismiss()
                            }
                        }
                    }) {
                        if viewModel.isPosting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("投稿する")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                    .disabled(viewModel.isPosting || viewModel.isFetchingPreview || viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedChannel == nil)
                    .opacity((viewModel.isPosting || viewModel.isFetchingPreview || viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedChannel == nil) ? 0.5 : 1.0)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                // タップでキーボードを閉じる
                isCommentFocused = false
                isSearchFocused = false
            }
        }
    }

    var body: some View {
        let _ = print("🎵 [CreatePostView in CreatePostView.swift] body evaluated - NEW VERSION")

        NavigationStack {
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView
                    contentAreaView

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            Task {
                await viewModel.warmupSearch()
                // チャンネルリストをリフレッシュして最新の状態にする
                await viewModel.loadUserChannels()
            }
        }
        .sheet(isPresented: $viewModel.showingCreateChannelSheet, onDismiss: {
            print("🔚 [CreatePostView] Channel creation sheet dismissed, postCreated: \(viewModel.postCreated)")
            // シートが閉じられたらフォームをクリア
            viewModel.newChannelName = ""
            viewModel.newChannelType = .personal
            viewModel.errorMessage = nil

            // 投稿成功後はpostCreatedフラグをリセット
            if viewModel.postCreated {
                print("🔄 [CreatePostView] Resetting postCreated flag")
                viewModel.postCreated = false
            }
        }) {
            if #available(iOS 16.4, *) {
                CreateChannelSheet(viewModel: viewModel)
                    .presentationBackground(Color.clear)
                    .background(Color.black)
            } else {
                CreateChannelSheet(viewModel: viewModel)
                    .background(Color.black)
            }
        }
        .sheet(isPresented: $showingChannelPostSheet, onDismiss: {
            // Reload channels to refresh the list
            Task {
                await viewModel.loadUserChannels()
            }
        }) {
            if let channel = selectedChannelForPost {
                if #available(iOS 16.4, *) {
                    CreatePostViewForChannel(
                        channel: channel,
                        latestPostArtworkUrl: nil
                    )
                    .environmentObject(authManager)
                    .presentationBackground(Color.clear)
                    .background(Color.black)
                } else {
                    CreatePostViewForChannel(
                        channel: channel,
                        latestPostArtworkUrl: nil
                    )
                    .environmentObject(authManager)
                    .background(Color.black)
                }
            }
        }
    }
}

// MARK: - Channel Row View for Create Post
struct ChannelRowViewForCreatePost: View {
    let channel: Channel

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
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Create Channel Sheet
struct CreateChannelSheet: View {
    @ObservedObject var viewModel: CreatePostViewModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var isChannelNameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 40)

                    // Title
                    VStack(spacing: 8) {
                        Text("新しいチャンネルを作成")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("このチャンネルに最初の投稿を追加します")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Selected song info
                    if let selectedSong = viewModel.selectedSong {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("投稿する曲")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.6))

                            HStack(spacing: 12) {
                                if let artwork = selectedSong.artwork {
                                    AsyncImage(url: artwork.url(width: 40, height: 40)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 40, height: 40)
                                                .clipped()
                                                .cornerRadius(6)
                                        default:
                                            Rectangle()
                                                .fill(Color.white.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(6)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedSong.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(selectedSong.artistName)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 24)
                    }

                    // Channel name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("チャンネル名")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        TextField("例: お気に入りの洋楽", text: $viewModel.newChannelName)
                            .padding()
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .focused($isChannelNameFocused)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                isChannelNameFocused = false
                            }
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("完了") {
                                        isChannelNameFocused = false
                                    }
                                }
                            }

                        Text("30文字以内")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 24)

                    // Channel type selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("チャンネルタイプ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        HStack(spacing: 12) {
                            // Personal channel button
                            Button(action: {
                                viewModel.newChannelType = .personal
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 16))
                                    Text("個人")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(viewModel.newChannelType == .personal ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    viewModel.newChannelType == .personal ?
                                    Color.white.opacity(0.3) : Color.white.opacity(0.1)
                                )
                                .cornerRadius(10)
                            }

                            // Shared channel button
                            Button(action: {
                                viewModel.newChannelType = .shared
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16))
                                    Text("公開")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(viewModel.newChannelType == .shared ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    viewModel.newChannelType == .shared ?
                                    Color.white.opacity(0.3) : Color.white.opacity(0.1)
                                )
                                .cornerRadius(10)
                            }
                        }

                        Text(viewModel.newChannelType == .personal ?
                             "自分だけが投稿できます" : "誰でも参加して投稿できます")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Error message
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    // Create button
                    Button(action: {
                        // キーボードを閉じる
                        isChannelNameFocused = false

                        Task {
                            await viewModel.createChannelAndPost()
                            // 成功したらシートを閉じる（createChannelAndPost内で既にfalseに設定されている）
                            // ここでdismiss()は不要（viewModel.showingCreateChannelSheetがfalseになれば自動的に閉じる）
                        }
                    }) {
                        if viewModel.isPosting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("チャンネルを作成して投稿")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                    .disabled(viewModel.isPosting || viewModel.newChannelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedSong == nil || viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((viewModel.isPosting || viewModel.newChannelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.selectedSong == nil || viewModel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct MusicKitSearchRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                AsyncImage(url: artwork.url(width: 50, height: 50)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    @unknown default:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .foregroundColor(.white)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                if let albumTitle = song.albumTitle {
                    Text(albumTitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}
