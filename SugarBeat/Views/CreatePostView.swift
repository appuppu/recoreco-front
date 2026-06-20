import SwiftUI
import MusicKit

struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = CreatePostViewModel()
    @FocusState private var isCommentFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @Binding var postCreated: Bool

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

                // Search button
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
            emptyStateView
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("曲を検索して投稿しよう")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    // Comment field (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("コメント（任意）")
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
                                Text("この曲についてのコメント...")
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

                    // Post button
                    Button(action: {
                        // Close keyboard
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
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.purple, Color.pink]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                    }
                    .disabled(viewModel.isPosting || viewModel.isFetchingPreview)
                    .opacity((viewModel.isPosting || viewModel.isFetchingPreview) ? 0.5 : 1.0)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isCommentFocused = false
                isSearchFocused = false
            }
        }
    }

    var body: some View {
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
            }
        }
    }
}

// MARK: - Music Kit Search Row
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
