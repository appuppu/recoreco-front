import Foundation
import MusicKit
import AVFoundation

@MainActor
class MusicKitManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined

    static let shared = MusicKitManager()

    let player = ApplicationMusicPlayer.shared
    private var avPlayer: AVPlayer?

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = MusicAuthorization.currentStatus
        isAuthorized = authorizationStatus == .authorized
    }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authorizationStatus = status
        isAuthorized = status == .authorized
    }

    func searchMusic(query: String, limit: Int = 10) async throws -> [Song] {
        // Request authorization if not already authorized
        if authorizationStatus != .authorized {
            await requestAuthorization()
        }

        guard authorizationStatus == .authorized else {
            throw MusicKitError.notAuthorized
        }

        // Use MusicKit's native search
        var searchRequest = MusicCatalogSearchRequest(term: query, types: [Song.self])
        searchRequest.limit = limit

        let searchResponse = try await searchRequest.response()
        return Array(searchResponse.songs)
    }

    func playPreviewFromURL(_ urlString: String, startTime: TimeInterval = 0) async throws {
        guard let url = URL(string: urlString) else {
            throw MusicKitError.invalidURL
        }

        // Stop any existing playback
        stopPreview()

        // Create new AVPlayer
        avPlayer = AVPlayer(url: url)

        // Seek to start time if specified
        if startTime > 0 {
            let time = CMTime(seconds: startTime, preferredTimescale: 600)
            await avPlayer?.seek(to: time)
        }

        // Start playback
        avPlayer?.play()
    }

    func stopPreview() {
        avPlayer?.pause()
        avPlayer = nil
    }

    var currentPlaybackTime: TimeInterval {
        return avPlayer?.currentTime().seconds ?? 0
    }

    func playSong(_ song: Song, startTime: TimeInterval = 0) async throws {
        // Set the queue with the song
        player.queue = [song]

        // Start playback
        try await player.prepareToPlay()

        // Seek to start time if specified
        if startTime > 0 {
            player.playbackTime = startTime
        }

        try await player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
    }
}

enum MusicKitError: Error {
    case notAuthorized
    case searchFailed
    case tokenFailed
    case invalidURL
}
