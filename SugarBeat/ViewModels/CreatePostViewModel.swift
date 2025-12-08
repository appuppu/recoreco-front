import Foundation
import MusicKit

@MainActor
class CreatePostViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [Song] = []
    @Published var selectedSong: Song?
    @Published var comment = ""
    @Published var isSearching = false
    @Published var isPosting = false
    @Published var isPlaying = false
    @Published var postCreated = false
    @Published var errorMessage: String?
    @Published var isFetchingPreview = false

    private let musicKitManager = MusicKitManager.shared
    private var previewURL: String?
    private var searchTask: Task<Void, Never>?

    init() {
        // No automatic search - user must press search button
    }

    func requestMusicAuthorization() async {
        await musicKitManager.requestAuthorization()
    }

    // Warmup search to initialize MusicKit and API connections
    func warmupSearch() async {
        await musicKitManager.warmupSearch()
    }

    // Public method to be called when search button is pressed
    func performSearch() async {
        // Cancel any ongoing search
        searchTask?.cancel()

        // Start new search task and wait for it to complete
        searchTask = Task {
            await searchMusic()
        }

        // Wait for the search task to complete
        await searchTask?.value
    }

    private func searchMusic() async {
        guard !searchQuery.isEmpty else {
            print("🔍🔍 SearchMusic: searchQuery is empty, returning")
            return
        }

        print("🔍🔍 SearchMusic: Starting search for query: '\(searchQuery)'")
        isSearching = true
        errorMessage = nil

        do {
            // Use MusicKit directly for better Japanese music search
            print("🔍🔍 SearchMusic: Calling musicKitManager.searchMusic...")
            let results = try await musicKitManager.searchMusic(query: searchQuery, limit: 25)
            print("🔍🔍 SearchMusic: MusicKit returned \(results.count) results")

            // Log first few results for debugging
            if !results.isEmpty {
                for (index, song) in results.prefix(3).enumerated() {
                    print("🔍🔍 SearchMusic: Result[\(index)]: \(song.title) by \(song.artistName)")
                }
            }

            searchResults = results
            print("🔍🔍 SearchMusic: Assigned results to searchResults. searchResults.count = \(searchResults.count)")

            if searchResults.isEmpty {
                print("🔍🔍 SearchMusic: Results are empty, setting error message")
                errorMessage = "検索結果が見つかりませんでした"
            }
        } catch is CancellationError {
            // Search was cancelled, don't show error
            print("🔍🔍 SearchMusic: Search was cancelled")
            searchResults = []
            errorMessage = nil
        } catch {
            // Only show error for actual failures, not cancellations
            print("🔍🔍 SearchMusic: Search failed with error: \(error)")
            if !Task.isCancelled {
                errorMessage = "音楽検索に失敗しました"
            }
        }

        isSearching = false
        print("🔍🔍 SearchMusic: Finished. Final searchResults.count = \(searchResults.count)")
    }

    func selectSong(_ song: Song) async {
        selectedSong = song
        searchResults = []
        searchQuery = ""

        // Fetch preview URL with retries
        await fetchPreviewURL(for: song)
    }

    private func fetchPreviewURL(for song: Song, retryCount: Int = 0) async {
        isFetchingPreview = true
        errorMessage = nil

        // First try to get preview from MusicKit Song object directly
        if #available(iOS 16.0, *), let previewAsset = song.previewAssets?.first {
            previewURL = previewAsset.url?.absoluteString
            isFetchingPreview = false
            if previewURL == nil {
                errorMessage = "この曲には30秒プレビューがありません"
            }
            return
        }

        // Fallback: Try to fetch from backend API
        do {
            let songDetails = try await APIClient.shared.getSongDetails(songId: song.id.rawValue)
            print("📀 Song details response: \(songDetails)")

            // Parse preview URL from Apple Music API response
            if let data = songDetails["data"] as? [[String: Any]],
               let firstSong = data.first,
               let attributes = firstSong["attributes"] as? [String: Any] {

                // Try previews array first
                if let previews = attributes["previews"] as? [[String: Any]],
                   let firstPreview = previews.first,
                   let url = firstPreview["url"] as? String {
                    previewURL = url
                    isFetchingPreview = false
                    print("📀 Found preview URL from previews: \(url)")
                    return
                }

                // Try previewURL field directly
                if let url = attributes["previewURL"] as? String {
                    previewURL = url
                    isFetchingPreview = false
                    print("📀 Found preview URL from previewURL: \(url)")
                    return
                }

                print("📀 No preview found in attributes: \(attributes.keys)")
            }

            // No preview available in response - retry up to 2 times
            if retryCount < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                await fetchPreviewURL(for: song, retryCount: retryCount + 1)
            } else {
                previewURL = nil
                isFetchingPreview = false
                errorMessage = "この曲には30秒プレビューがありません"
            }
        } catch {
            print("📀 Error fetching song details: \(error)")
            // Network error - retry up to 2 times
            if retryCount < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
                await fetchPreviewURL(for: song, retryCount: retryCount + 1)
            } else {
                previewURL = nil
                isFetchingPreview = false
                errorMessage = "プレビューの取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    func playPreview() async {
        guard let previewURLString = previewURL else {
            errorMessage = "プレビューURLがありません。この曲にはプレビューがありません。"
            return
        }

        do {
            try await musicKitManager.playPreviewFromURL(previewURLString)
            isPlaying = true

            // Auto-stop after 30 seconds
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if isPlaying {
                    stopPreview()
                }
            }
        } catch {
            errorMessage = "再生に失敗しました: \(error.localizedDescription)"
        }
    }

    func stopPreview() {
        musicKitManager.stopPreview()
        isPlaying = false
    }

    func createPost() async {
        guard let song = selectedSong else {
            errorMessage = "曲が選択されていません"
            return
        }

        isPosting = true
        errorMessage = nil

        do {
            // Validate required fields
            let trackId = song.id.rawValue
            let trackName = song.title
            let artistName = song.artistName

            guard !trackId.isEmpty else {
                errorMessage = "トラックIDが無効です"
                isPosting = false
                return
            }

            guard !trackName.isEmpty else {
                errorMessage = "曲名が無効です"
                isPosting = false
                return
            }

            guard !artistName.isEmpty else {
                errorMessage = "アーティスト名が無効です"
                isPosting = false
                return
            }

            // Validate comment is not empty
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedComment.isEmpty {
                errorMessage = "紹介文を入力してください"
                isPosting = false
                return
            }

            // Validate comment length
            if trimmedComment.count > 50 {
                errorMessage = "紹介文は50文字以内で入力してください"
                isPosting = false
                return
            }

            // Get artwork URL
            let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString

            // Fixed 30-second preview (0 to 30 seconds)
            let startTime: Double = 0
            let endTime: Double = 30

            let request = CreatePostRequest(
                appleMusicTrackId: trackId,
                trackName: trackName,
                artistName: artistName,
                albumName: song.albumTitle,
                artworkUrl: artworkUrl,
                previewUrl: previewURL,
                appleMusicUrl: song.url?.absoluteString,
                comment: trimmedComment,
                startTime: startTime,
                endTime: endTime
            )

            _ = try await APIClient.shared.createPost(request: request)

            // Clear state and mark as created
            stopPreview()
            postCreated = true
            errorMessage = nil

            // フィード更新通知を発行
            NotificationCenter.default.post(name: Foundation.Notification.Name.postCreated, object: nil)

            // Reset form
            selectedSong = nil
            comment = ""
            searchQuery = ""
            searchResults = []
        } catch APIError.unauthorized {
            errorMessage = "認証エラー"
            postCreated = false
        } catch APIError.invalidResponse {
            errorMessage = "サーバーエラー"
            postCreated = false
        } catch APIError.decodingFailed {
            errorMessage = "紹介は成功しましたが、表示に問題があります"
            // Still mark as created since post was likely successful
            postCreated = true

            // フィード更新通知を発行
            NotificationCenter.default.post(name: Foundation.Notification.Name.postCreated, object: nil)

            // Reset form
            stopPreview()
            selectedSong = nil
            comment = ""
            searchQuery = ""
            searchResults = []
        } catch {
            errorMessage = "紹介に失敗しました"
            postCreated = false
        }

        isPosting = false
    }
}
