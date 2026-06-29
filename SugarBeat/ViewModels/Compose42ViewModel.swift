//
//  Compose42ViewModel.swift
//  SugarBeat
//

import Foundation
import MusicKit
import FirebaseAuth

enum LayoutType: String, CaseIterable {
    case vertical = "縦画面(Instagramなど)"
    case horizontal = "横画面(Xなど)"
}

/// 選曲の取得元
enum ComposeSource: String, CaseIterable {
    case search = "検索"
    case myPosts = "自分の投稿"
}

struct SelectedTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    /// 検索由来の場合はMusicKitのSong（プレビュー再生に使用）。自分の投稿由来の場合はnil。
    let song: Song?
    /// 自分の投稿由来の場合に保持するプレビューURL（MusicKit再解決を避ける）。
    let previewUrlString: String?

    init(from song: Song) {
        self.id = song.id.rawValue
        self.title = song.title
        self.artist = song.artistName
        self.artworkURL = song.artwork?.url(width: 600, height: 600)
        self.song = song
        self.previewUrlString = song.previewAssets?.first?.url?.absoluteString
    }

    /// 自分の投稿（Post）からトラックを生成する。
    /// 保存済みの artworkUrl をそのまま使い、MusicKitでの再解決は行わない（パフォーマンス維持のため）。
    init(from post: Post) {
        // appleMusicTrackId があればそれをID、なければ投稿IDで一意化
        self.id = post.appleMusicTrackId ?? (post.id ?? UUID().uuidString)
        self.title = post.trackName ?? "(タイトルなし)"
        self.artist = post.artistName ?? ""
        self.artworkURL = post.artworkUrl.flatMap { URL(string: $0) }
        self.song = nil
        self.previewUrlString = post.previewUrl
    }

    static func == (lhs: SelectedTrack, rhs: SelectedTrack) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class Compose42ViewModel: ObservableObject {
    @Published var selectedTracks: [SelectedTrack] = []
    @Published var layoutType: LayoutType = .vertical {
        didSet {
            print("🎨 [Compose42ViewModel] Layout type changed: \(oldValue.rawValue) → \(layoutType.rawValue)")
        }
    }
    @Published var isShowingPreview: Bool = false {
        didSet {
            print("🎨 [Compose42ViewModel] isShowingPreview changed: \(oldValue) → \(isShowingPreview)")
        }
    }

    // Source toggle: 検索 or 自分の投稿
    @Published var source: ComposeSource = .search

    // Search
    @Published var searchQuery: String = ""
    @Published var searchResults: [Song] = []
    @Published var isSearching: Bool = false

    // My posts
    @Published var myPosts: [Post] = []
    @Published var isLoadingMyPosts: Bool = false
    private var myPostsLoaded = false

    // Playback
    @Published var currentPlayingTrackId: String? = nil

    private let musicKitManager = MusicKitManager.shared
    private let maxTracks = 42

    init() {
        // シート表示時にバックグラウンドで"a"を検索してキャッシュ
        Task {
            await preloadSearch()
        }
    }

    var canComplete: Bool {
        selectedTracks.count == maxTracks
    }

    var tracksRemaining: Int {
        maxTracks - selectedTracks.count
    }

    private func preloadSearch() async {
        do {
            // 検索してキャッシュするだけ（結果は表示しない）
            _ = try await musicKitManager.searchMusic(query: "a", limit: 25)
            print("🎵 [Compose42] Preload search completed (cached, not displayed)")
        } catch {
            print("❌ [Compose42] Preload search failed: \(error)")
        }
    }

    func searchMusic() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await musicKitManager.searchMusic(query: searchQuery, limit: 25)
            searchResults = results
            print("🎵 [Compose42] Search completed: \(results.count) results for '\(searchQuery)'")
        } catch {
            print("❌ [Compose42] Search failed: \(error)")
            searchResults = []
        }
    }

    /// 自分の投稿一覧を取得する。保存済みの artworkUrl をそのまま使うため、
    /// MusicKitでの再解決は行わない（アルバムアート表示のパフォーマンス維持）。
    func loadMyPosts(forceRefresh: Bool = false) async {
        guard !isLoadingMyPosts else { return }
        if myPostsLoaded && !forceRefresh { return }

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            print("⚠️ [Compose42] loadMyPosts: not authenticated")
            return
        }

        isLoadingMyPosts = true
        defer { isLoadingMyPosts = false }

        do {
            // 多めに取得して42枚を選びやすくする（音楽投稿のみ対象）
            let (fetchedPosts, _) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId, limit: 100)
            myPosts = fetchedPosts
                .filter { ($0.contentType ?? ContentType.music.rawValue) == ContentType.music.rawValue }
                .filter { $0.artworkUrl != nil }
                .sorted { $0.createdAt > $1.createdAt }
            myPostsLoaded = true
            print("✅ [Compose42] Loaded \(myPosts.count) of my music posts")
        } catch {
            print("❌ [Compose42] Failed to load my posts: \(error)")
        }
    }

    func addTrack(_ song: Song) {
        appendTrack(SelectedTrack(from: song))
    }

    /// 自分の投稿からトラックを追加する。
    func addTrack(from post: Post) {
        appendTrack(SelectedTrack(from: post))
    }

    private func appendTrack(_ track: SelectedTrack) {
        guard selectedTracks.count < maxTracks else {
            print("⚠️ [Compose42] Cannot add more tracks, limit reached")
            return
        }

        // Check if already added
        guard !selectedTracks.contains(where: { $0.id == track.id }) else {
            print("⚠️ [Compose42] Track already added: \(track.title)")
            return
        }

        selectedTracks.append(track)
        print("✅ [Compose42] Track added: \(track.title) (\(selectedTracks.count)/\(maxTracks))")
    }

    func removeTrack(at index: Int) {
        guard index < selectedTracks.count else { return }
        let track = selectedTracks[index]
        selectedTracks.remove(at: index)
        print("🗑️ [Compose42] Track removed: \(track.title) (\(selectedTracks.count)/\(maxTracks))")
    }

    func removeTrack(id: String) {
        if let index = selectedTracks.firstIndex(where: { $0.id == id }) {
            removeTrack(at: index)
        }
    }

    func playPreview(for track: SelectedTrack) async {
        // 検索由来はSongから、自分の投稿由来は保存済みのpreviewUrlから取得
        guard let previewURL = track.previewUrlString ?? track.song?.previewAssets?.first?.url?.absoluteString else {
            print("⚠️ [Compose42] No preview available for: \(track.title)")
            return
        }

        do {
            currentPlayingTrackId = track.id
            try await musicKitManager.playPreviewFromURL(previewURL)
            print("▶️ [Compose42] Playing preview: \(track.title)")
        } catch {
            print("❌ [Compose42] Failed to play preview: \(error)")
            currentPlayingTrackId = nil
        }
    }

    func stopPreview() {
        musicKitManager.stopPreview()
        currentPlayingTrackId = nil
        print("⏹️ [Compose42] Stopped preview")
    }

    func showPreview() {
        guard canComplete else {
            print("⚠️ [Compose42ViewModel] Cannot show preview: \(selectedTracks.count)/\(maxTracks) tracks")
            return
        }
        print("🎨 [Compose42ViewModel] Showing preview with layout: \(layoutType.rawValue)")
        isShowingPreview = true
    }

    func reset() {
        selectedTracks = []
        searchQuery = ""
        searchResults = []
        isShowingPreview = false
        stopPreview()
        // 自分の投稿・取得元はリセットしない（再取得コストを避けるため保持）
        print("🔄 [Compose42] Reset")
    }
}
