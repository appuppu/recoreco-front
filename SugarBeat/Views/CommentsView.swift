import SwiftUI
import FirebaseAuth

/// YouTubeスタイルのコメント表示View
struct CommentsView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var commentStateManager = CommentStateManager.shared
    @StateObject private var musicKit = MusicKitManager.shared
    @StateObject private var playbackState = PlaybackStateManager.shared
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var showingDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var errorMessage: String?
    @State private var showingReportComment = false
    @State private var showingPostError = false
    @State private var postErrorMessage = ""
    @State private var postUser: User? = nil
    @State private var commentToReport: Comment?
    @State private var justPosted = false
    @State private var previousCommentCount = 0
    @State private var selectedComment: Comment? = nil  // 返信画面用
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        VStack(spacing: 0) {
            // ドラッグハンドル
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // ヘッダー
            HStack {
                Text("コメント")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(comments.count)")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.1))

            // 投稿表示
            postCard
                .padding(.vertical, 12)

            Divider()
                .background(Color.white.opacity(0.1))

            // コメントリスト
            if isLoading && comments.isEmpty {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            } else if let error = errorMessage, comments.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.red.opacity(0.7))
                    Text(error)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            } else if comments.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.4))
                    Text("コメントはまだありません")
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(comments, id: \.id) { comment in
                            CommentRowYouTube(
                                comment: comment,
                                onDelete: {
                                    commentToDelete = comment
                                    showingDeleteAlert = true
                                },
                                onReport: {
                                    commentToReport = comment
                                    showingReportComment = true
                                },
                                onShowReplies: {
                                    selectedComment = comment
                                },
                                onLikeToggle: {
                                    Task {
                                        await toggleCommentLike(comment)
                                    }
                                }
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 12)

                            Divider()
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
            }

            // コメント入力
            if authManager.isAuthenticated {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: authManager.currentUser?.profileImageUrl ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    TextField("コメントする...", text: $newCommentText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                        .disabled(isPosting)

                    if !newCommentText.isEmpty {
                        Button(action: {
                            Task {
                                await postComment()
                            }
                        }) {
                            Image(systemName: isPosting ? "arrow.up.circle" : "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(isPosting ? .gray : .white)
                        }
                        .disabled(isPosting)
                    }
                }
                .padding()
                .background(Color.black)
            }
        }
        .background(Color.black)
        .presentationDetents([.height(UIScreen.main.bounds.height * 0.7), .large])
        .presentationDragIndicator(.hidden)
        .task {
            await loadComments()
            postUser = try? await FirestoreUserManager.shared.getUser(userId: post.userId)
            previousCommentCount = comments.count
        }
        .alert("コメントを削除しますか？", isPresented: $showingDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let comment = commentToDelete {
                    Task {
                        await deleteComment(comment)
                    }
                }
            }
        }
        .alert("エラー", isPresented: $showingPostError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(postErrorMessage)
        }
        .sheet(isPresented: $showingReportComment) {
            if let comment = commentToReport {
                ReportCommentView(comment: comment)
            }
        }
        .sheet(item: $selectedComment) { comment in
            CommentRepliesView(post: post, parentComment: comment)
        }
    }

    // MARK: - Post Card
    private var postCard: some View {
        HStack(spacing: 12) {
            // アルバムアートワーク
            AsyncImage(url: URL(string: post.artworkUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(post.contentTitle ?? post.trackName ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(post.contentDescription ?? post.artistName ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                if let user = postUser {
                    HStack(spacing: 4) {
                        AsyncImage(url: URL(string: user.profileImageUrl ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())

                        Text("@\(user.username)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            Spacer()

            // 再生ボタン
            if let postId = post.id {
                Button(action: {
                    Task {
                        await togglePlayback()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 40, height: 40)

                        if musicKit.isLoadingPreview && playbackState.currentlyPlayingPostId == postId {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: playbackState.isPlaying(postId) ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Functions
    private func togglePlayback() async {
        guard let postId = post.id else { return }

        if playbackState.isPlaying(postId) {
            musicKit.stopPreview()
            playbackState.stopPlayback()
        } else {
            if let previewUrl = post.previewUrl {
                do {
                    try await musicKit.playPreviewFromURL(previewUrl, startTime: post.startTime ?? 0)
                    playbackState.startPlayback(for: postId, userId: post.userId, post: post, user: postUser)
                } catch {
                    print("❌ Failed to play preview: \(error)")
                }
            }
        }
    }

    private func loadComments() async {
        guard let postId = post.id else { return }
        isLoading = true
        errorMessage = nil

        do {
            let (fetchedComments, _) = try await FirestoreCommentManager.shared.getComments(postId: postId)
            comments = fetchedComments
        } catch {
            errorMessage = "コメントの読み込みに失敗しました"
            print("Failed to load comments: \(error)")
        }

        isLoading = false
    }

    private func postComment() async {
        guard let postId = post.id,
              let currentUserId = Auth.auth().currentUser?.uid,
              let currentUser = authManager.currentUser else { return }

        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isPosting = true
        justPosted = false

        do {
            let comment = Comment(from: currentUser, postId: postId, content: text)
            _ = try await FirestoreCommentManager.shared.createComment(comment)
            newCommentText = ""
            commentStateManager.incrementCount(postId: postId)

            withAnimation {
                justPosted = true
            }

            await loadComments()

            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation {
                justPosted = false
            }
        } catch {
            print("Failed to post comment: \(error)")
            postErrorMessage = "コメントの投稿に失敗しました。もう一度お試しください。"
            showingPostError = true
        }

        isPosting = false
    }

    private func deleteComment(_ comment: Comment) async {
        guard let commentId = comment.id, let postId = post.id else { return }

        do {
            try await FirestoreCommentManager.shared.deleteComment(postId: postId, commentId: commentId)
            commentStateManager.decrementCount(postId: postId)
            await loadComments()
        } catch {
            print("Failed to delete comment: \(error)")
            postErrorMessage = "コメントの削除に失敗しました。もう一度お試しください。"
            showingPostError = true
        }
    }

    private func toggleCommentLike(_ comment: Comment) async {
        guard let commentId = comment.id, let postId = post.id else { return }

        do {
            if comment.isLiked {
                try await FirestoreCommentManager.shared.unlikeComment(postId: postId, commentId: commentId)
            } else {
                try await FirestoreCommentManager.shared.likeComment(postId: postId, commentId: commentId)
            }
            await loadComments()
        } catch {
            print("Failed to toggle comment like: \(error)")
        }
    }
}

// MARK: - Comment Row YouTube Style
struct CommentRowYouTube: View {
    let comment: Comment
    let onDelete: () -> Void
    let onReport: () -> Void
    let onShowReplies: () -> Void
    let onLikeToggle: () -> Void
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingActionSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // プロフィール画像
                AsyncImage(url: URL(string: comment.userProfileImageUrl ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image("recoreco")
                        .resizable()
                        .scaledToFill()
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("@\(comment.username)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)

                        Text(formatDate(comment.createdAt))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(comment.content)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    // いいねボタン
                    Button(action: onLikeToggle) {
                        HStack(spacing: 4) {
                            Image(systemName: comment.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12))
                                .foregroundColor(comment.isLiked ? .white : .white.opacity(0.6))

                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }

                Spacer()

                // メニューボタン
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
            }

            // 返信ボタン
            HStack(spacing: 16) {
                // 返信がない場合は「返信」ボタン、ある場合は「x件の返信」のみ表示
                if comment.replyCount > 0 {
                    Button(action: onShowReplies) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)

                            Text("\(comment.replyCount)件の返信")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    Button(action: onShowReplies) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))

                            Text("返信")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.leading, 48)
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            if let currentUserId = authManager.currentUser?.id, currentUserId == comment.userId {
                Button("削除", role: .destructive) {
                    onDelete()
                }
            } else {
                Button("報告", role: .destructive) {
                    onReport()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Comment Replies View
struct CommentRepliesView: View {
    let post: Post
    let parentComment: Comment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var commentStateManager = CommentStateManager.shared
    @State private var replies: [Comment] = []
    @State private var newReplyText = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var showingDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var showingReportComment = false
    @State private var commentToReport: Comment?
    @State private var postErrorMessage = ""
    @State private var showingPostError = false
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("返信")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()

            Divider()
                .background(Color.white.opacity(0.1))

            // 親コメント + 返信リスト
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 親コメント
                    CommentRowSimple(
                        comment: parentComment,
                        onLikeToggle: {
                            Task {
                                await toggleCommentLike(parentComment)
                            }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.03))

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // 返信リスト
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding()
                    } else {
                        ForEach(replies, id: \.id) { reply in
                            CommentRowSimple(
                                comment: reply,
                                onDelete: {
                                    commentToDelete = reply
                                    showingDeleteAlert = true
                                },
                                onReport: {
                                    commentToReport = reply
                                    showingReportComment = true
                                },
                                onLikeToggle: {
                                    Task {
                                        await toggleCommentLike(reply)
                                    }
                                }
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .padding(.leading, 48)

                            Divider()
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
            }

            // 返信入力
            if authManager.isAuthenticated {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: authManager.currentUser?.profileImageUrl ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    TextField("返信を追加...", text: $newReplyText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                        .disabled(isPosting)

                    if !newReplyText.isEmpty {
                        Button(action: {
                            Task {
                                await postReply()
                            }
                        }) {
                            Image(systemName: isPosting ? "arrow.up.circle" : "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(isPosting ? .gray : .white)
                        }
                        .disabled(isPosting)
                    }
                }
                .padding()
                .background(Color.black)
            }
        }
        .background(Color.black)
        .presentationDetents([.large])
        .task {
            await loadReplies()
        }
        .alert("コメントを削除しますか？", isPresented: $showingDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let comment = commentToDelete {
                    Task {
                        await deleteComment(comment)
                    }
                }
            }
        }
        .alert("エラー", isPresented: $showingPostError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(postErrorMessage)
        }
        .sheet(isPresented: $showingReportComment) {
            if let comment = commentToReport {
                ReportCommentView(comment: comment)
            }
        }
    }

    private func loadReplies() async {
        guard let postId = post.id, let parentId = parentComment.id else { return }
        isLoading = true

        do {
            replies = try await FirestoreCommentManager.shared.getReplies(postId: postId, parentCommentId: parentId)
        } catch {
            print("Failed to load replies: \(error)")
        }

        isLoading = false
    }

    private func postReply() async {
        guard let postId = post.id,
              let parentId = parentComment.id,
              let currentUser = authManager.currentUser else { return }

        let text = newReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isPosting = true

        do {
            let reply = Comment(from: currentUser, postId: postId, content: text, parentCommentId: parentId)
            _ = try await FirestoreCommentManager.shared.createComment(reply)
            newReplyText = ""
            await loadReplies()
        } catch {
            print("Failed to post reply: \(error)")
            postErrorMessage = "返信の投稿に失敗しました。もう一度お試しください。"
            showingPostError = true
        }

        isPosting = false
    }

    private func deleteComment(_ comment: Comment) async {
        guard let commentId = comment.id, let postId = post.id else { return }

        do {
            try await FirestoreCommentManager.shared.deleteComment(postId: postId, commentId: commentId)
            await loadReplies()
        } catch {
            print("Failed to delete comment: \(error)")
            postErrorMessage = "コメントの削除に失敗しました。もう一度お試しください。"
            showingPostError = true
        }
    }

    private func toggleCommentLike(_ comment: Comment) async {
        guard let commentId = comment.id, let postId = post.id else { return }

        do {
            if comment.isLiked {
                try await FirestoreCommentManager.shared.unlikeComment(postId: postId, commentId: commentId)
            } else {
                try await FirestoreCommentManager.shared.likeComment(postId: postId, commentId: commentId)
            }
            await loadReplies()
        } catch {
            print("Failed to toggle comment like: \(error)")
        }
    }
}

// MARK: - Comment Row Simple (for Replies)
struct CommentRowSimple: View {
    let comment: Comment
    var onDelete: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onLikeToggle: (() -> Void)? = nil
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingActionSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // プロフィール画像
            AsyncImage(url: URL(string: comment.userProfileImageUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image("recoreco")
                    .resizable()
                    .scaledToFill()
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("@\(comment.username)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(formatDate(comment.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(comment.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                // いいねボタン
                if let onLikeToggle = onLikeToggle {
                    Button(action: onLikeToggle) {
                        HStack(spacing: 4) {
                            Image(systemName: comment.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12))
                                .foregroundColor(comment.isLiked ? .white : .white.opacity(0.6))

                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
            }

            Spacer()

            // メニューボタン（onDelete/onReportがある場合のみ）
            if onDelete != nil || onReport != nil {
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
            }
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            if let currentUserId = authManager.currentUser?.id, currentUserId == comment.userId, let onDelete = onDelete {
                Button("削除", role: .destructive) {
                    onDelete()
                }
            } else if let onReport = onReport {
                Button("報告", role: .destructive) {
                    onReport()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
