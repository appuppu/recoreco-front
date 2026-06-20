import SwiftUI

/// 投稿を縦スクロールで表示する汎用フィード
///
/// - 1投稿 = 1カード（FeaturedPostCellSimple = プロフィールの大セルと同じ表示）を縦に並べるタイムライン形式
/// - 投稿者アイコン・ユーザー名・日付・プロフィール遷移・報告/削除/ブロックはセル側が担当
/// - 広告は「2投稿 → 広告 → 1投稿 → 広告 → 2投稿 → 広告 → 1投稿 …」のパターンで挟む
/// - 末尾付近までスクロールしたら onLoadMore を呼んで追加読み込み
struct ScrollableFeedView: View {
    let posts: [Post]
    let isLoading: Bool
    let isLoadingMore: Bool
    let onLoadMore: () async -> Void
    let onRefresh: () async -> Void

    @Binding var showingLoginPrompt: Bool
    var scrollToTopTrigger: Int = 0 // 値が変わると一番上へスクロール

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width
            // プロフィールの大セルと同じく正方形を基本サイズにする
            let cardHeight = cardWidth

            ZStack {
                Color.black.ignoresSafeArea()

                if posts.isEmpty && isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if posts.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                // 一番上へスクロールするためのアンカー
                                Color.clear
                                    .frame(height: 0)
                                    .id("feed-top")

                                ForEach(Array(feedItems.enumerated()), id: \.offset) { _, item in
                                    switch item {
                                    case .post(let post, let globalIndex):
                                        FeaturedPostCellSimple(
                                            post: post,
                                            width: cardWidth,
                                            height: cardHeight,
                                            showingLoginPrompt: $showingLoginPrompt,
                                            showUserInfo: true,
                                            showDate: false,
                                            safeAreaTop: 0
                                        )
                                        .frame(width: cardWidth, height: cardHeight)
                                        .onAppear {
                                            // 末尾2件手前で追加読み込み
                                            if globalIndex >= posts.count - 2 {
                                                Task { await onLoadMore() }
                                            }
                                        }
                                    case .ad(let adIndex):
                                        if AdConfig.shouldShowAds {
                                            FeedAdCardView()
                                                .id("ad-\(adIndex)")
                                        }
                                    }
                                }

                                if isLoadingMore {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.vertical, 20)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .refreshable {
                            await onRefresh()
                        }
                        .onChange(of: scrollToTopTrigger) { _ in
                            withAnimation {
                                proxy.scrollTo("feed-top", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("投稿がありません")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 広告挟み込みパターン

    /// フィードに表示する要素（投稿 or 広告）
    private enum FeedItem {
        case post(Post, globalIndex: Int)
        case ad(Int)
    }

    /// posts に「2投稿→広告→1投稿→広告→2投稿→広告→1投稿…」のパターンで広告を差し込んだ配列を生成
    private var feedItems: [FeedItem] {
        var items: [FeedItem] = []
        var adCount = 0
        var i = 0
        // 2個 → 1個 → 2個 → 1個 … と交互に投稿を出し、その都度広告を挟む（2個始まり）
        var takeOne = false

        while i < posts.count {
            let take = takeOne ? 1 : 2
            for _ in 0..<take {
                guard i < posts.count else { break }
                items.append(.post(posts[i], globalIndex: i))
                i += 1
            }
            // まだ投稿が残っている場合のみ広告を挟む（末尾の余分な広告を避ける）
            if i < posts.count {
                items.append(.ad(adCount))
                adCount += 1
            }
            takeOne.toggle()
        }

        return items
    }
}
