import SwiftUI
import MusicKit

struct ContentView: View {
    @State private var refreshFeedTrigger = false

    var body: some View {
        FeedView(refreshTrigger: $refreshFeedTrigger)
    }
}

struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = CreatePostViewModel()
    @FocusState private var isCommentFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @Binding var postCreated: Bool
    @Binding var tutorialStep: TutorialStep
    @Binding var showingInteractiveTutorial: Bool

    var body: some View {
        NavigationStack {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Fixed header with close button and search bar
                VStack(spacing: 12) {
                    // Close button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Text("新規音楽紹介")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        // Placeholder for symmetry
                        Color.clear.frame(width: 28, height: 28)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Search bar - Fixed position
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.6))
                            TextField("曲名、アーティスト名で検索", text: $viewModel.searchQuery)
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .focused($isSearchFocused)
                                .onSubmit {
                                    Task {
                                        await viewModel.performSearch()
                                        // チュートリアルステップを進める
                                        if tutorialStep == .searchSong && !viewModel.searchResults.isEmpty {
                                            tutorialStep = .selectSong
                                        }
                                    }
                                }
                                .onChange(of: isSearchFocused) { focused in
                                    print("⌨️ Search focus changed: \(focused), tutorialStep: \(tutorialStep)")
                                    // キーボードが表示されたらチュートリアルモーダルを消す
                                    if focused && tutorialStep == .searchSong {
                                        showingInteractiveTutorial = false
                                        print("⌨️ Hiding tutorial modal because keyboard is shown")
                                    }
                                }
                            if !viewModel.searchQuery.isEmpty {
                                Button(action: { viewModel.searchQuery = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)

                        // 検索ボタン
                        Button(action: {
                            print("🔍🔍🔍 SEARCH BUTTON TAPPED - query: '\(viewModel.searchQuery)', tutorialStep: \(tutorialStep)")
                            // キーボードを閉じる
                            isSearchFocused = false

                            Task {
                                print("🔍 Starting search...")
                                await viewModel.performSearch()
                                print("🔍 Search finished - results count: \(viewModel.searchResults.count)")
                                // チュートリアルステップを進める
                                if tutorialStep == .searchSong && !viewModel.searchResults.isEmpty {
                                    tutorialStep = .selectSong
                                    showingInteractiveTutorial = true
                                    print("🔍 Search completed - moving to selectSong step, showing tutorial: \(showingInteractiveTutorial)")
                                } else {
                                    print("🔍 Not moving to next step - tutorialStep: \(tutorialStep), results: \(viewModel.searchResults.count)")
                                }
                            }
                        }) {
                            Text("検索")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.searchQuery.isEmpty || viewModel.isSearching)
                    }
                    .padding(.horizontal)
                }
                .background(Color.clear)
                .padding(.bottom, 8)

                // Scrollable content area
                if viewModel.isSearching {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                } else if !viewModel.searchResults.isEmpty {
                    // Search results
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.searchResults, id: \.id) { song in
                                Button(action: {
                                    Task {
                                        await viewModel.selectSong(song)
                                        // チュートリアルステップを進める
                                        if tutorialStep == .selectSong {
                                            tutorialStep = .tapPostButton
                                            showingInteractiveTutorial = true
                                            print("🎵 Song selected - moving to tapPostButton step, showing tutorial: \(showingInteractiveTutorial)")
                                        }
                                    }
                                }) {
                                    MusicKitSearchRow(song: song)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let selectedSong = viewModel.selectedSong {
                    // Selected song and post creation
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
                            TextEditor(text: $viewModel.comment)
                                .frame(height: 80)
                                .padding(8)
                                .background(Color(.systemGray6))
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
                        .padding(.horizontal)

                        // Post button
                        Button(action: {
                            print("📝 Post button tapped - current tutorialStep: \(tutorialStep)")
                            let wasTutorial = tutorialStep == .tapPostButton
                            print("📝 wasTutorial: \(wasTutorial)")

                            Task {
                                await viewModel.createPost()
                                if viewModel.postCreated {
                                    postCreated = true
                                    print("📝 Post created successfully, dismissing CreatePostView")

                                    // チュートリアル中でも通常でも、すぐに閉じる
                                    // 完了モーダルはFeedViewで表示される
                                    dismiss()
                                }
                            }
                        }) {
                            if viewModel.isPosting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("この内容で紹介する")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                        }
                        .disabled(viewModel.isPosting || viewModel.isFetchingPreview)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .padding(.top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("曲を検索して紹介")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxHeight: .infinity)
                }

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

            // Interactive Tutorial Overlay (completedステップはFeedViewで表示される)
            if showingInteractiveTutorial && (tutorialStep == .searchSong || tutorialStep == .selectSong || tutorialStep == .tapPostButton) {
                InteractiveTutorialView(
                    isPresented: $showingInteractiveTutorial,
                    currentStep: $tutorialStep,
                    targetFrame: nil,
                    onNext: {
                        // このビューでは.completedステップは表示しない
                    }
                )
            }
        }
        .navigationBarHidden(true)
        }
        .onAppear {
            print("🎨 CreatePostView appeared - tutorialStep: \(tutorialStep), showingInteractiveTutorial: \(showingInteractiveTutorial)")
            // Warmup search to initialize MusicKit and API connections
            Task {
                await viewModel.warmupSearch()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
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

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
