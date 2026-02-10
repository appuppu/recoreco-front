//
//  Compose42View.swift
//  SugarBeat
//

import SwiftUI
import MusicKit

struct Compose42View: View {
    @StateObject private var viewModel = Compose42ViewModel()
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss

    @State private var showingCloseConfirmation = false
    @State private var showingLoginPromotion = false

    var body: some View {
        ZStack {
            if viewModel.isShowingPreview {
                PreviewGridView(
                    tracks: viewModel.selectedTracks,
                    layoutType: viewModel.layoutType,
                    onClose: {
                        showingCloseConfirmation = true
                    }
                )
                .onAppear {
                    print("🎨 [Compose42View] PreviewGridView appeared with layoutType: \(viewModel.layoutType.rawValue)")
                }
            } else {
                SelectionView(
                    viewModel: viewModel,
                    onClose: {
                        showingCloseConfirmation = true
                    }
                )
            }
        }
        .confirmationDialog("", isPresented: $showingCloseConfirmation, titleVisibility: .hidden) {
            Button("戻る") {
                viewModel.isShowingPreview = false
            }
            Button("閉じる", role: .destructive) {
                handleClose()
            }
        }
        .alert("ログインすると便利！", isPresented: $showingLoginPromotion) {
            Button("OK") {
                showAdAndDismiss()
            }
        } message: {
            Text("ログインすると自分の投稿の中からいつでも私を構成する42枚を作成できて検索の手間がなくなるよ！")
        }
    }

    private func handleClose() {
        if authManager.isAuthenticated {
            // ログイン済み: 直接広告表示
            showAdAndDismiss()
        } else {
            // 未ログイン: ログイン促進メッセージ表示
            showingLoginPromotion = true
        }
    }

    private func showAdAndDismiss() {
        // Load and show interstitial ad
        let adManager = InterstitialAdManager.shared
        adManager.load()

        // Wait briefly for ad to load, then show
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let rootVC = adManager.getRootViewController() {
                adManager.show(from: rootVC)
            }
            // Dismiss after showing ad or if ad fails
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismiss()
            }
        }
    }
}

// MARK: - Selection View
struct SelectionView: View {
    @ObservedObject var viewModel: Compose42ViewModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search Bar
                    SearchBarView(
                        searchQuery: $viewModel.searchQuery,
                        onSearch: {
                            Task {
                                await viewModel.searchMusic()
                            }
                        }
                    )
                    .padding()

                    // Search Results
                    if !viewModel.searchResults.isEmpty {
                        SearchResultsListView(
                            results: viewModel.searchResults,
                            selectedTracks: viewModel.selectedTracks,
                            currentPlayingId: viewModel.currentPlayingTrackId,
                            onAdd: { song in
                                viewModel.addTrack(song)
                            },
                            onPlay: { song in
                                let track = SelectedTrack(from: song)
                                Task {
                                    await viewModel.playPreview(for: track)
                                }
                            },
                            onStopPlay: {
                                viewModel.stopPreview()
                            }
                        )
                        .frame(height: 250)
                    }

                    // Selected Tracks Grid
                    ScrollView {
                        VStack(spacing: 12) {
                            // Header
                            HStack {
                                Text("私を構成する42枚")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(viewModel.selectedTracks.count)/42")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(viewModel.canComplete ? .green : .white.opacity(0.6))
                            }
                            .padding(.horizontal)

                            // Grid
                            SelectedTracksGrid(
                                tracks: viewModel.selectedTracks,
                                layoutType: viewModel.layoutType,
                                onRemove: { track in
                                    viewModel.removeTrack(id: track.id)
                                }
                            )
                            .padding(.horizontal)

                            // Layout Type Picker
                            Picker("画面タイプ", selection: $viewModel.layoutType) {
                                ForEach(LayoutType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.top, 8)

                            // OK Button
                            Button {
                                viewModel.showPreview()
                            } label: {
                                Text("OK")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        viewModel.canComplete
                                        ? LinearGradient(colors: [Color.purple, Color.pink], startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [Color.gray, Color.gray], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .cornerRadius(12)
                            }
                            .disabled(!viewModel.canComplete)
                            .padding(.horizontal)
                            .padding(.top, 16)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.reset()
                    } label: {
                        Text("リセット")
                            .foregroundColor(.red)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}

// MARK: - Search Bar View
struct SearchBarView: View {
    @Binding var searchQuery: String
    let onSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("曲名、アーティスト名で検索", text: $searchQuery)
                .foregroundColor(.white)
                .onSubmit {
                    onSearch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Search Results List View
struct SearchResultsListView: View {
    let results: [Song]
    let selectedTracks: [SelectedTrack]
    let currentPlayingId: String?
    let onAdd: (Song) -> Void
    let onPlay: (Song) -> Void
    let onStopPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("検索結果")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.id) { song in
                        let isAdded = selectedTracks.contains(where: { $0.id == song.id.rawValue })
                        SearchResultRow(
                            song: song,
                            isAdded: isAdded,
                            isPlaying: currentPlayingId == song.id.rawValue,
                            onAdd: { onAdd(song) },
                            onPlay: {
                                if currentPlayingId == song.id.rawValue {
                                    onStopPlay()
                                } else {
                                    onPlay(song)
                                }
                            }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Color.white.opacity(0.05))
        }
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let song: Song
    let isAdded: Bool
    let isPlaying: Bool
    let onAdd: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            if let artworkURL = song.artwork?.url(width: 60, height: 60) {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(song.artistName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Play Button
            Button {
                onPlay()
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(18)
            }

            // Add Button
            Button {
                onAdd()
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        isAdded
                        ? LinearGradient(colors: [Color.gray, Color.gray], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.purple, Color.pink], startPoint: .leading, endPoint: .trailing)
                    )
            }
            .disabled(isAdded)
        }
    }
}

// MARK: - Selected Tracks Grid
struct SelectedTracksGrid: View {
    let tracks: [SelectedTrack]
    let layoutType: LayoutType
    let onRemove: (SelectedTrack) -> Void

    private var columns: Int {
        layoutType == .vertical ? 6 : 7
    }

    private var rows: Int {
        layoutType == .vertical ? 7 : 6
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let cellSize = (geometry.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(0..<(columns * rows), id: \.self) { index in
                    if index < tracks.count {
                        let track = tracks[index]
                        TrackCell(track: track, cellSize: cellSize, onRemove: {
                            onRemove(track)
                        })
                    } else {
                        EmptyCell(cellSize: cellSize)
                    }
                }
            }
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .animation(.easeInOut(duration: 0.3), value: layoutType)
        .onAppear {
            print("🎨 [SelectedTracksGrid] Layout: \(layoutType.rawValue), columns: \(columns), rows: \(rows)")
        }
        .onChange(of: layoutType) { newValue in
            print("🎨 [SelectedTracksGrid] Layout changed to: \(newValue.rawValue), columns: \(columns), rows: \(rows)")
        }
    }
}

// MARK: - Track Cell
struct TrackCell: View {
    let track: SelectedTrack
    let cellSize: CGFloat
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Artwork
            if let url = track.artworkURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
            } else {
                Color.gray.opacity(0.3)
            }

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)).padding(2))
            }
            .padding(4)
        }
        .frame(width: cellSize, height: cellSize)
        .cornerRadius(4)
        .clipped()
    }
}

// MARK: - Empty Cell
struct EmptyCell: View {
    let cellSize: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: cellSize, height: cellSize)
            .cornerRadius(4)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: cellSize * 0.3))
                    .foregroundColor(.white.opacity(0.3))
            )
    }
}

// MARK: - Preview Grid View
struct PreviewGridView: View {
    let tracks: [SelectedTrack]
    let layoutType: LayoutType
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if layoutType == .vertical {
                        VerticalLayoutView(tracks: tracks, screenSize: geometry.size)
                            .onAppear {
                                print("🎨 [PreviewGridView] Rendering VerticalLayoutView")
                            }
                    } else {
                        // 横画面モード: 90度回転してスマホを横に傾けたような表示に
                        HorizontalLayoutView(
                            tracks: tracks,
                            screenSize: CGSize(width: geometry.size.height, height: geometry.size.width)
                        )
                        .frame(width: geometry.size.height, height: geometry.size.width) // 回転前のサイズ
                        .rotationEffect(.degrees(-90))
                        .frame(width: geometry.size.width, height: geometry.size.height) // 回転後、画面にフィット
                        .onAppear {
                            print("🎨 [PreviewGridView] Rendering HorizontalLayoutView with rotation: screen=\(geometry.size), rotated=\(CGSize(width: geometry.size.height, height: geometry.size.width))")
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onClose()
            }
            .onAppear {
                print("🎨 [PreviewGridView] Layout type: \(layoutType.rawValue), rawValue comparison: vertical=\(layoutType == .vertical), horizontal=\(layoutType == .horizontal)")
            }
        }
    }
}

// MARK: - Vertical Layout View
struct VerticalLayoutView: View {
    let tracks: [SelectedTrack]
    let screenSize: CGSize

    private let columns = 6
    private let rows = 7

    var body: some View {
        VStack(spacing: 0) {
            // Grid
            let spacing: CGFloat = 2
            let gridWidth = screenSize.width
            let cellSize = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(tracks.indices, id: \.self) { index in
                    if let url = tracks[index].artworkURL {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: cellSize, height: cellSize)
                        .clipped()
                    }
                }
            }

            // Track Info (6 columns, each column shows 7 tracks vertically)
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<columns, id: \.self) { col in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<rows, id: \.self) { row in
                            let index = col + row * columns
                            if index < tracks.count {
                                let track = tracks[index]
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 8))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(height: 8 * 2 + 1, alignment: .top) // 2行分の固定高さ
                                    Text(track.artist)
                                        .font(.system(size: 7))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(height: 7 * 2 + 1, alignment: .top) // 2行分の固定高さ
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                    .frame(width: cellSize)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - Horizontal Layout View
struct HorizontalLayoutView: View {
    let tracks: [SelectedTrack]
    let screenSize: CGSize

    // 90度回転後に6列×7行に見えるように、7列×6行で定義
    private let columns = 7
    private let rows = 6

    var body: some View {
        HStack(spacing: 0) {
            // Grid (left side, 70% width - 7 columns × 6 rows, will be 6×7 after rotation)
            let spacing: CGFloat = 2
            let gridWidth = screenSize.width * 0.7
            let availableHeight = screenSize.height

            // セルサイズを幅と高さの両方から計算して、画面にピッタリ収める
            let cellSizeByWidth = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellSizeByHeight = (availableHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let cellSize = min(cellSizeByWidth, cellSizeByHeight)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { col in
                            let index = col + row * columns
                            if index < tracks.count, let url = tracks[index].artworkURL {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: cellSize, height: cellSize)
                                .clipped()
                            }
                        }
                    }
                }
            }
            .frame(width: gridWidth, height: availableHeight, alignment: .leading)

            // Track Info (right side, 30% width - 6 row groups, each group shows 7 tracks vertically)
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    // 各行内の7つの曲を均等配置するための高さ計算
                    let trackHeight = (cellSize - 2 * CGFloat(columns - 1)) / CGFloat(columns)
                    let _ = print("🎨 [HorizontalLayoutView] Row \(row): cellSize=\(cellSize), trackHeight=\(trackHeight), calculation: (\(cellSize) - 2 * \(columns - 1)) / \(columns)")

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<columns, id: \.self) { col in
                            let index = col + row * columns
                            if index < tracks.count {
                                let track = tracks[index]
                                HStack(spacing: 4) {
                                    Text(track.title)
                                        .font(.system(size: 6))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.system(size: 5))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                                .frame(width: cellSize * 3, height: trackHeight, alignment: .leading) // 高さを均等に配置
                                .background(Color.red.opacity(0.1)) // デバッグ用の背景色
                                .onAppear {
                                    if col == 0 && row == 0 {
                                        print("🎨 [HorizontalLayoutView] First track frame: width=\(cellSize * 3), height=\(trackHeight)")
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: cellSize, alignment: .top) // 各行グループを cellSize の高さに固定
                }
            }
            .frame(width: screenSize.width * 0.3, height: availableHeight, alignment: .topLeading)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .onAppear {
            let spacing: CGFloat = 2
            let gridWidth = screenSize.width * 0.7
            let availableHeight = screenSize.height
            let cellSizeByWidth = (gridWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellSizeByHeight = (availableHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let cellSize = min(cellSizeByWidth, cellSizeByHeight)
            print("🎨 [HorizontalLayoutView] Screen size: \(screenSize), Grid: \(gridWidth)x\(availableHeight), Cell size: \(cellSize) (by width: \(cellSizeByWidth), by height: \(cellSizeByHeight))")
        }
    }
}
