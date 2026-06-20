import SwiftUI
import FirebaseAuth

/// 再利用可能なフォロー/フォロー解除ボタン
///
/// - 表示時に自分がそのユーザーをフォロー済みか確認し、状態に応じて見た目を切り替える
/// - タップで楽観的にUIを更新し、Firestoreへ反映（失敗時はロールバック）
/// - 自分自身には表示しない
/// - onChange で親にフォロー状態の変化を通知できる（カウント更新などに使う）
struct FollowButton: View {
    let userId: String
    var compact: Bool = false // 小さめ表示（一覧・検索結果用）
    var onChange: ((Bool) -> Void)? = nil // フォロー状態が変わったとき(true=フォローした)

    @State private var isFollowing = false
    @State private var isLoading = true
    @State private var isProcessing = false

    private var isSelf: Bool {
        Auth.auth().currentUser?.uid == userId
    }

    var body: some View {
        Group {
            if isSelf {
                EmptyView()
            } else {
                Button(action: toggleFollow) {
                    Text(isFollowing ? "フォロー中" : "フォロー")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundColor(isFollowing ? .white.opacity(0.9) : .white)
                        .padding(.horizontal, compact ? 14 : 20)
                        .padding(.vertical, compact ? 6 : 8)
                        .background(
                            Group {
                                if isFollowing {
                                    Color.white.opacity(0.15)
                                } else {
                                    LinearGradient(
                                        colors: [Color.purple, Color.pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(isFollowing ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .disabled(isProcessing || isLoading)
                .opacity(isLoading ? 0.5 : 1.0)
            }
        }
        .task {
            await loadFollowState()
        }
    }

    private func loadFollowState() async {
        guard !isSelf else { isLoading = false; return }
        isFollowing = (try? await FirestoreFollowManager.shared.isFollowing(userId: userId)) ?? false
        isLoading = false
    }

    private func toggleFollow() {
        guard !isProcessing else { return }
        let wasFollowing = isFollowing
        // 楽観的更新
        isFollowing.toggle()
        isProcessing = true
        onChange?(isFollowing)

        Task {
            do {
                if wasFollowing {
                    try await FirestoreFollowManager.shared.unfollowUser(userId: userId)
                } else {
                    try await FirestoreFollowManager.shared.followUser(userId: userId)
                }
            } catch {
                // 失敗したらロールバック
                isFollowing = wasFollowing
                onChange?(isFollowing)
                print("❌ Failed to toggle follow: \(error)")
            }
            isProcessing = false
        }
    }
}
