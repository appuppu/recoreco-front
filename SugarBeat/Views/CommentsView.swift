import SwiftUI

/// コメント表示用View（シート用）
struct CommentsView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var commentStateManager = CommentStateManager.shared
    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var showingDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var errorMessage: String?
    @State private var showingReportComment = false
    @State private var commentToReport: Comment?
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Post info header
                HStack(spacing: 12) {
                    // Album artwork
                    AsyncImage(url: URL(string: post.artworkUrl ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        // Track name
                        Text(post.trackName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        // Artist name
                        Text(post.artistName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)

                        // User info
                        HStack(spacing: 6) {
                            AsyncImage(url: URL(string: APIClient.shared.getFullImageURL(post.user.profileImageUrl) ?? "")) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())

                            Text(post.user.displayName)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        // Comment text
                        if let comment = post.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(Color.white.opacity(0.05))

                Divider()
                    .background(Color.white.opacity(0.2))

                // Comments list
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
                                CommentRow(
                                    comment: comment,
                                    onDelete: {
                                        commentToDelete = comment
                                        showingDeleteAlert = true
                                    },
                                    onReport: {
                                        commentToReport = comment
                                        showingReportComment = true
                                    }
                                )
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }

                // Comment input
                if authManager.isAuthenticated {
                    HStack(spacing: 12) {
                        TextField("コメントを入力...", text: $newCommentText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(20)

                        Button(action: {
                            Task {
                                await postComment()
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(newCommentText.isEmpty ? .gray : .purple)
                        }
                        .disabled(newCommentText.isEmpty)
                    }
                    .padding()
                    .background(Color.black)
                }
            }
        }
        .navigationTitle("コメント")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("閉じる") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await loadComments()
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
        .sheet(isPresented: $showingReportComment) {
            if let comment = commentToReport {
                ReportCommentView(comment: comment)
            }
        }
    }

    private func loadComments() async {
        isLoading = true
        errorMessage = nil

        do {
            comments = try await APIClient.shared.getComments(postId: post.id)
        } catch {
            errorMessage = "コメントの読み込みに失敗しました"
            print("Failed to load comments: \(error)")
        }

        isLoading = false
    }

    private func postComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            let request = CreateCommentRequest(postId: post.id, content: text)
            let newComment = try await APIClient.shared.createComment(request: request)
            comments.insert(newComment, at: 0)
            newCommentText = ""
            // Update comment count
            commentStateManager.incrementCount(postId: post.id)
        } catch {
            print("Failed to post comment: \(error)")
        }
    }

    private func deleteComment(_ comment: Comment) async {
        do {
            try await APIClient.shared.deleteComment(commentId: comment.id)
            comments.removeAll { $0.id == comment.id }
            // Update comment count
            commentStateManager.decrementCount(postId: post.id)
        } catch {
            print("Failed to delete comment: \(error)")
        }
    }
}

// MARK: - Comment Row
struct CommentRow: View {
    let comment: Comment
    let onDelete: () -> Void
    let onReport: () -> Void
    @EnvironmentObject private var authManager: AuthManager
    @State private var showingActionSheet = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile image
            AsyncImage(url: URL(string: APIClient.shared.getFullImageURL(comment.user.profileImageUrl) ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.2))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.user.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text(formatDate(comment.createdAt))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(comment.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }

            // More button
            Button(action: {
                showingActionSheet = true
            }) {
                Image(systemName: "ellipsis")
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 30, height: 30)
            }
        }
        .confirmationDialog("", isPresented: $showingActionSheet, titleVisibility: .hidden) {
            if let currentUserId = authManager.currentUser?.userId, currentUserId == comment.user.id {
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
