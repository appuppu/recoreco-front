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

    // Channel fields
    @Published var channels: [Channel] = []
    @Published var selectedChannel: Channel?
    @Published var isLoadingChannels = false
    @Published var showingCreateChannelSheet = false
    @Published var newChannelName = ""
    @Published var newChannelType: ChannelType = .personal

    // Computed property: channels that user can post to
    var postableChannels: [Channel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }

        return channels.filter { channel in
            switch channel.channelType {
            case .personal:
                // Can only post to own personal channels
                return channel.userId == currentUserId
            case .shared:
                // Can post to all shared channels (public channels are open to everyone)
                return true
            }
        }
    }

    // Common fields
    @Published var comment = ""
    @Published var isPosting = false
    @Published var postCreated = false
    @Published var errorMessage: String?

    private let musicKitManager = MusicKitManager.shared
    private var searchTask: Task<Void, Never>?

    init() {
        print("🎬 [CreatePostViewModel] init() - Loading channels on initialization")
        // Load user's channels on init
        Task {
            await loadUserChannels()
        }

        // チャンネル作成/削除通知を監視
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name("ChannelCreated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("📥 [CreatePostViewModel] Received ChannelCreated notification")
                await self?.loadUserChannels()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name("ChannelDeleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("📥 [CreatePostViewModel] Received ChannelDeleted notification")
                await self?.loadUserChannels()
            }
        }

        // 投稿作成通知を監視（チャンネルのlatestPostAtを更新するため）
        NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.postCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                print("📥 [CreatePostViewModel] Received postCreated notification, reloading channels to update latestPostAt...")
                await self?.loadUserChannels()
            }
        }
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


    func loadUserChannels() async {
        print("🔄 [CreatePostViewModel] loadUserChannels started")
        isLoadingChannels = true

        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                isLoadingChannels = false
                return
            }
            print("✅ [CreatePostViewModel] Current userId: \(currentUserId)")

            // Load both own channels and followed channels
            let ownChannels = try await FirestoreChannelManager.shared.getUserChannels(userId: currentUserId)
            print("✅ [CreatePostViewModel] Fetched \(ownChannels.count) own channels")
            let followedChannels = try await FirestoreChannelManager.shared.getFollowedChannels(userId: currentUserId)
            print("✅ [CreatePostViewModel] Fetched \(followedChannels.count) followed channels")

            // Merge and remove duplicates
            var allChannels = ownChannels
            for followedChannel in followedChannels {
                if !allChannels.contains(where: { $0.id == followedChannel.id }) {
                    allChannels.append(followedChannel)
                }
            }

            channels = allChannels

            // Log channel types breakdown
            let sharedCount = channels.filter { $0.channelType == .shared }.count
            let personalCount = channels.filter { $0.channelType == .personal }.count
            print("✅ [CreatePostViewModel] Total channels: \(channels.count) (shared: \(sharedCount), personal: \(personalCount))")

            // Log personal channels details
            let personalChannels = channels.filter { $0.channelType == .personal }
            for channel in personalChannels {
                let latestPostDate = channel.latestPostAt?.formatted() ?? "No posts"
                print("📋 [CreatePostViewModel] Personal Channel: \(channel.name) | ID: \(channel.id ?? "nil") | Latest: \(latestPostDate)")
            }

            // Auto-select first postable channel if available
            if !postableChannels.isEmpty && selectedChannel == nil {
                selectedChannel = postableChannels[0]
            }
        } catch {
            print("❌ Failed to load user channels: \(error)")
            errorMessage = "チャンネルの読み込みに失敗しました"
        }

        isLoadingChannels = false
    }

    func createChannelAndPost() async {
        isPosting = true
        errorMessage = nil

        do {
            // Get current user ID
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                errorMessage = "認証エラー"
                isPosting = false
                return
            }

            // Validate channel name
            let trimmedChannelName = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedChannelName.isEmpty {
                errorMessage = "チャンネル名を入力してください"
                isPosting = false
                return
            }

            if trimmedChannelName.count > 30 {
                errorMessage = "チャンネル名は30文字以内で入力してください"
                isPosting = false
                return
            }

            // Validate comment
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedComment.isEmpty {
                errorMessage = "紹介文を入力してください"
                isPosting = false
                return
            }

            if trimmedComment.count > 50 {
                errorMessage = "紹介文は50文字以内で入力してください"
                isPosting = false
                return
            }

            // Validate song selection
            guard let song = selectedSong else {
                errorMessage = "曲が選択されていません"
                isPosting = false
                return
            }

            // Create channel first - pass channelType explicitly
            let newChannel = try await FirestoreChannelManager.shared.createChannel(
                name: trimmedChannelName,
                channelType: newChannelType
            )

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

            // Create music post with channel info (only IDs, no denormalized data)
            let post = Post(
                userId: currentUserId,
                channelId: newChannel.id,
                appleMusicTrackId: song.id.rawValue,
                trackName: song.title,
                artistName: song.artistName,
                albumName: song.albumTitle,
                artworkUrl: artworkUrl,
                artistImageUrl: artistImageUrl,
                previewUrl: previewURL,
                appleMusicUrl: song.url?.absoluteString,
                comment: trimmedComment,
                startTime: 0,
                endTime: 30
            )

            // Create post in Firestore
            let createdPostId = try await FirestorePostManager.shared.createPost(post)

            // Update channel's latest post info
            do {
                try await FirestoreChannelManager.shared.updateChannelLatestPost(
                    channelId: newChannel.id ?? "",
                    postId: createdPostId,
                    artworkUrl: artworkUrl
                )
            } catch {
                // Log error but don't fail the post creation
                print("⚠️ Failed to update channel latest post: \(error)")
            }

            // Clear state and mark as created
            stopPreview()
            postCreated = true
            errorMessage = nil
            newChannelName = ""
            showingCreateChannelSheet = false

            // フィード更新通知を発行
            NotificationCenter.default.post(name: Foundation.Notification.Name.postCreated, object: nil)

            // チャンネル作成通知を発行
            NotificationCenter.default.post(name: Foundation.Notification.Name("ChannelCreated"), object: nil)

            // Reload channels
            await loadUserChannels()

            // Reset form
            resetForm()
        } catch {
            errorMessage = "作成に失敗しました: \(error.localizedDescription)"
            postCreated = false
        }

        isPosting = false
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

            // Validate channel selection
            guard let channel = selectedChannel else {
                errorMessage = "チャンネルを選択してください"
                isPosting = false
                return
            }

            // Validate channel ID
            guard let channelId = channel.id, !channelId.isEmpty else {
                errorMessage = "無効なチャンネルです。チャンネルリストを更新してください。"
                isPosting = false
                // Reload channels to fix inconsistency
                await loadUserChannels()
                return
            }

            // Validate comment
            let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedComment.isEmpty {
                errorMessage = "紹介文を入力してください"
                isPosting = false
                return
            }

            if trimmedComment.count > 50 {
                errorMessage = "紹介文は50文字以内で入力してください"
                isPosting = false
                return
            }

            // Validate song selection
            guard let song = selectedSong else {
                errorMessage = "曲が選択されていません"
                isPosting = false
                return
            }

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

            // Create music post with channel info (only IDs, no denormalized data)
            let post = Post(
                userId: currentUserId,
                channelId: channel.id,
                appleMusicTrackId: song.id.rawValue,
                trackName: song.title,
                artistName: song.artistName,
                albumName: song.albumTitle,
                artworkUrl: artworkUrl,
                artistImageUrl: artistImageUrl,
                previewUrl: previewURL,
                appleMusicUrl: song.url?.absoluteString,
                comment: trimmedComment,
                startTime: 0,
                endTime: 30
            )

            // Debug: Log post details before creating
            print("🔍 [CreatePostViewModel] Creating post with:")
            print("   - userId: \(post.userId)")
            print("   - channelId: \(post.channelId ?? "nil")")
            print("   - createdAt: \(post.createdAt)")
            print("   - updatedAt: \(post.updatedAt)")
            print("   - createdAt type: \(type(of: post.createdAt))")
            print("   - updatedAt type: \(type(of: post.updatedAt))")

            // Create post in Firestore
            let createdPostId = try await FirestorePostManager.shared.createPost(post)
            print("✅ [CreatePostViewModel] Post created successfully with ID: \(createdPostId)")

            // Update channel's latest post info (only if user is channel owner)
            print("🔍 [CreatePostViewModel] Checking channel update condition:")
            print("   - channelId: \(channel.id ?? "nil")")
            print("   - channel.userId: \(channel.userId)")
            print("   - currentUserId: \(currentUserId)")
            print("   - Condition met: \(channel.id != nil && channel.userId == currentUserId)")

            if let channelId = channel.id, channel.userId == currentUserId {
                print("✅ [CreatePostViewModel] Updating channel metadata for channelId: \(channelId)")
                do {
                    try await FirestoreChannelManager.shared.updateChannelLatestPost(
                        channelId: channelId,
                        postId: createdPostId,
                        artworkUrl: artworkUrl
                    )
                    print("✅ [CreatePostViewModel] Channel metadata updated successfully")
                } catch {
                    // Log error but don't fail the post creation
                    print("⚠️ [CreatePostViewModel] Failed to update channel metadata: \(error)")
                }
            } else {
                print("⚠️ [CreatePostViewModel] Skipped channel metadata update - condition not met")
                if channel.id == nil {
                    print("   - Reason: channelId is nil")
                }
                if channel.userId != currentUserId {
                    print("   - Reason: channel.userId (\(channel.userId)) != currentUserId (\(currentUserId))")
                }
            }

            // Clear state and mark as created
            stopPreview()
            postCreated = true
            errorMessage = nil

            // フィード更新通知を発行
            print("📢 [CreatePostViewModel] Posting notification: postCreated for postId: \(createdPostId)")
            NotificationCenter.default.post(name: Foundation.Notification.Name.postCreated, object: nil)

            // Reset form
            resetForm()
        } catch {
            errorMessage = "紹介に失敗しました: \(error.localizedDescription)"
            postCreated = false
        }

        isPosting = false
    }

    private func resetForm() {
        selectedSong = nil
        comment = ""
        searchQuery = ""
        searchResults = []
        newChannelName = ""
        selectedChannel = nil
    }
}
