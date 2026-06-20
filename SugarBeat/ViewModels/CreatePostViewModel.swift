import Foundation
import MusicKit
import FirebaseAuth

@MainActor
class CreatePostViewModel: ObservableObject {
    // Music-specific fields
    @Published var searchQuery = ""
    @Published var searchResults: [Song] = []
    @Published var selectedSong: Song?
    @Published var isSearching = false
    @Published var isPlaying = false
    @Published var isFetchingPreview = false
    private var previewURL: String?

    // Common fields
    @Published var comment = ""  // Now optional
    @Published var isPosting = false
    @Published var postCreated = false
    @Published var errorMessage: String?

    private let musicKitManager = MusicKitManager.shared
    private var searchTask: Task<Void, Never>?

    init() {
        print("🎬 [CreatePostViewModel] init() - Channel-free version")
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
            print("🔍 SearchMusic: searchQuery is empty, returning")
            return
        }

        print("🔍 SearchMusic: Starting search for query: '\(searchQuery)'")
        isSearching = true
        errorMessage = nil

        do {
            let results = try await musicKitManager.searchMusic(query: searchQuery, limit: 25)
            print("🔍 SearchMusic: MusicKit returned \(results.count) results")

            searchResults = results

            if searchResults.isEmpty {
                errorMessage = "検索結果が見つかりませんでした"
            }
        } catch is CancellationError {
            print("🔍 SearchMusic: Search was cancelled")
            searchResults = []
            errorMessage = nil
        } catch {
            print("🔍 SearchMusic: Search failed with error: \(error)")
            if !Task.isCancelled {
                errorMessage = "音楽検索に失敗しました"
            }
        }

        isSearching = false
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
            }

            // No preview available in response - retry up to 2 times
            if retryCount < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await fetchPreviewURL(for: song, retryCount: retryCount + 1)
            } else {
                previewURL = nil
                isFetchingPreview = false
                errorMessage = "この曲には30秒プレビューがありません"
            }
        } catch {
            print("📀 Error fetching song details: \(error)")
            if retryCount < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await fetchPreviewURL(for: song, retryCount: retryCount + 1)
            } else {
                previewURL = nil
                isFetchingPreview = false
                errorMessage = "プレビューの取得に失敗しました"
            }
        }
    }

    func playPreview() async {
        guard let previewURLString = previewURL else {
            errorMessage = "プレビューURLがありません"
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
        isPosting = true
        errorMessage = nil

        do {
            // Get current user ID
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                errorMessage = "認証エラー"
                isPosting = false
                return
            }

            // Validate song selection
            guard let song = selectedSong else {
                errorMessage = "曲が選択されていません"
                isPosting = false
                return
            }

            // Comment is optional - trim but allow empty
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)

            // Get artwork URL
            let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString

            // Get artist image URL
            var artistImageUrl: String? = nil
            if let artist = song.artists?.first {
                do {
                    let artistRequest = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: artist.id)
                    let artistResponse = try await artistRequest.response()
                    if let fetchedArtist = artistResponse.items.first {
                        artistImageUrl = fetchedArtist.artwork?.url(width: 1000, height: 1000)?.absoluteString
                    }
                } catch {
                    print("⚠️ Failed to fetch artist artwork: \(error)")
                }
            }

            // Create music post without channel (channelId = nil)
            let post = Post(
                userId: currentUserId,
                channelId: nil,  // No channel
                appleMusicTrackId: song.id.rawValue,
                trackName: song.title,
                artistName: song.artistName,
                albumName: song.albumTitle,
                artworkUrl: artworkUrl,
                artistImageUrl: artistImageUrl,
                previewUrl: previewURL,
                appleMusicUrl: song.url?.absoluteString,
                comment: trimmedComment.isEmpty ? nil : trimmedComment,  // Nil if empty
                startTime: 0,
                endTime: 30
            )

            print("🔍 [CreatePostViewModel] Creating post:")
            print("   - userId: \(post.userId)")
            print("   - channelId: nil (channel-free)")
            print("   - comment: \(post.comment ?? "nil")")

            // Create post in Firestore
            let createdPostId = try await FirestorePostManager.shared.createPost(post)
            print("✅ [CreatePostViewModel] Post created successfully with ID: \(createdPostId)")

            // Clear state and mark as created
            stopPreview()
            postCreated = true
            errorMessage = nil

            // Send notification for feed refresh
            NotificationCenter.default.post(name: Foundation.Notification.Name.postCreated, object: nil)

            // Reset form
            resetForm()
        } catch {
            errorMessage = "投稿に失敗しました: \(error.localizedDescription)"
            postCreated = false
        }

        isPosting = false
    }

    private func resetForm() {
        selectedSong = nil
        comment = ""
        searchQuery = ""
        searchResults = []
    }
}
