//
//  Compose42ViewModel.swift
//  SugarBeat
//

import Foundation
import MusicKit

enum LayoutType: String, CaseIterable {
    case vertical = "縦画面(Instagramなど)"
    case horizontal = "横画面(Xなど)"
}

struct SelectedTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let song: Song

    init(from song: Song) {
        self.id = song.id.rawValue
        self.title = song.title
        self.artist = song.artistName
        self.artworkURL = song.artwork?.url(width: 600, height: 600)
        self.song = song
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

    // Search
    @Published var searchQuery: String = ""
    @Published var searchResults: [Song] = []
    @Published var isSearching: Bool = false

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

    func addTrack(_ song: Song) {
        guard selectedTracks.count < maxTracks else {
            print("⚠️ [Compose42] Cannot add more tracks, limit reached")
            return
        }

        let track = SelectedTrack(from: song)

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
        guard let previewURL = track.song.previewAssets?.first?.url?.absoluteString else {
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
        print("🔄 [Compose42] Reset")
    }
}
