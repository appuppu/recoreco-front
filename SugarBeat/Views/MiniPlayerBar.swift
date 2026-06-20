import SwiftUI

/// 画面全体で共有される「再生中バー（ミニプレーヤー）」。
///
/// - 何か再生中（PlaybackStateManager.currentlyPlayingInfo がある）のときだけ表示
/// - タブバーの少し上に浮かぶように配置（ContentView でオーバーレイする）
/// - 再生/停止ボタンと ✕ ボタン。✕ は再生停止してバーも消す
/// - デザインはコメント画面上部の曲ヘッダーに準拠（アートワーク + 曲名/アーティスト/本文）
struct MiniPlayerBar: View {
    @StateObject private var playbackState = PlaybackStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared

    var body: some View {
        if let info = playbackState.currentlyPlayingInfo {
            let post = info.post
            HStack(spacing: 12) {
                // アートワーク
                AsyncImage(url: URL(string: post.artworkUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)

                // 曲名 / アーティスト / 投稿本文（各1行）
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.contentTitle ?? post.trackName ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(post.contentDescription ?? post.artistName ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    if let comment = post.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // 再生 / 停止
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }

                // ✕（再生停止してバーも消す）
                Button(action: closePlayer) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
            )
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var isPlaying: Bool {
        musicKit.isPlaying
    }

    private func togglePlayback() {
        // togglePlayPause は既存の avPlayer を一時停止/再開する（再生位置を保持）
        musicKit.togglePlayPause()
    }

    private func closePlayer() {
        musicKit.stopPreview()
        playbackState.stopPlayback()
    }
}
