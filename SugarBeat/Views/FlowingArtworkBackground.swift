import SwiftUI

/// 投稿のアートワークをグリッドで敷き詰め、ゆっくり上に流れる背景演出。
///
/// - 全投稿のアートワークURLを取得してグリッド表示（プロフィールの大セルなし版＝均等グリッド）
/// - 同じグリッドを2枚縦に並べて無限ループでスクロールさせる
/// - 上に暗いオーバーレイを重ね、前面のテキスト/ボタンを読みやすくする
/// - 未ログインでも posts は読めるため、ログイン前の画面でも使える
struct FlowingArtworkBackground: View {
    var columns: Int = 3
    var scrollDuration: Double = 60 // 1ループにかける秒数（大きいほどゆっくり）

    @StateObject private var loader = ArtworkBackgroundLoader.shared
    @State private var offsetY: CGFloat = 0
    @State private var isScrolling = false

    /// グリッド1枚分（gridHeight）を scrollDuration 秒かけて上へ流し、無限ループさせる
    private func startScrolling(gridHeight: CGFloat) {
        guard gridHeight > 0, !isScrolling else { return }
        isScrolling = true
        offsetY = 0
        withAnimation(.linear(duration: scrollDuration).repeatForever(autoreverses: false)) {
            offsetY = -gridHeight
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let cellSize = width / CGFloat(columns)
            // グリッド1枚分の高さ（行数 = 全アートワーク / 列数）
            let rows = max(1, Int(ceil(Double(loader.artworkUrls.count) / Double(columns))))
            let gridHeight = cellSize * CGFloat(rows)

            ZStack {
                Color.black

                if !loader.artworkUrls.isEmpty && gridHeight > 0 {
                    // 同じグリッドを2枚縦に並べてループさせる
                    VStack(spacing: 0) {
                        artworkGrid(cellSize: cellSize)
                        artworkGrid(cellSize: cellSize)
                    }
                    .offset(y: offsetY)
                    .onAppear {
                        // すでにアートワークがある場合（キャッシュ復元時など）は即スクロール開始
                        startScrolling(gridHeight: gridHeight)
                    }
                    .onChange(of: gridHeight) { newHeight in
                        // データ取得後に高さが確定したタイミングでスクロール開始
                        startScrolling(gridHeight: newHeight)
                    }
                }

                // 暗いオーバーレイ（前面コンテンツの可読性確保）
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.75)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .task {
            await loader.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func artworkGrid(cellSize: CGFloat) -> some View {
        let cols = Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: columns)
        LazyVGrid(columns: cols, spacing: 0) {
            ForEach(Array(loader.artworkUrls.enumerated()), id: \.offset) { _, url in
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                }
                .frame(width: cellSize, height: cellSize)
                .clipped()
            }
        }
    }
}

/// 背景用アートワークURLの取得・キャッシュ（複数画面で共有）
///
/// - 端末ローカル(UserDefaults)にURLリストを永続保存する。
/// - 起動直後は保存済みURLを即座に表示（Firestore取得を待たない＝2回目以降はスプラッシュでも演出が見える）。
/// - 表示後、裏でFirestoreから最新を取得して保存（次回用に更新）。
@MainActor
class ArtworkBackgroundLoader: ObservableObject {
    static let shared = ArtworkBackgroundLoader()

    @Published var artworkUrls: [String] = []
    private var hasRefreshed = false
    private var isRefreshing = false

    private let cacheKey = "cached_background_artwork_urls"

    private init() {
        // 起動時、保存済みのアートワークURLを即座に読み込む（黒画面を最小化）
        if let saved = UserDefaults.standard.stringArray(forKey: cacheKey), !saved.isEmpty {
            artworkUrls = saved.shuffled()
            print("🎨 [ArtworkBackgroundLoader] Restored \(saved.count) cached artwork URLs")
        }
    }

    func loadIfNeeded() async {
        // 最新の取得は1セッション1回でよい（表示は既にキャッシュから出ている）
        guard !hasRefreshed, !isRefreshing else { return }
        isRefreshing = true

        do {
            // 全投稿から最大100件のアートワークを取得（背景用なのでざっくりで良い）
            let (posts, _) = try await FirestorePostManager.shared.getDiscoveryFeed(limit: 100)
            let urls = posts
                .compactMap { $0.artworkUrl }
                .filter { !$0.isEmpty }

            if !urls.isEmpty {
                // 次回起動用に永続保存
                UserDefaults.standard.set(urls, forKey: cacheKey)

                // 既に表示中（キャッシュ復元済み）の場合は、ちらつきを避けるため
                // 表示が空のときだけ即時反映する。表示中なら次回起動で反映される。
                if artworkUrls.isEmpty {
                    artworkUrls = urls.shuffled()
                }
                hasRefreshed = true
                print("🎨 [ArtworkBackgroundLoader] Refreshed \(urls.count) artwork URLs (saved for next launch)")
            }
        } catch {
            print("⚠️ [ArtworkBackgroundLoader] Failed to load artworks: \(error)")
        }

        isRefreshing = false
    }
}
