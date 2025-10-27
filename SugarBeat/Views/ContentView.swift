import SwiftUI
import MusicKit

struct ContentView: View {
    @State private var refreshFeedTrigger = false

    var body: some View {
        FeedView(refreshTrigger: $refreshFeedTrigger)
    }
}

struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = CreatePostViewModel()
    @FocusState private var isCommentFocused: Bool
    @Binding var postCreated: Bool

    var body: some View {
        NavigationStack {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.2, green: 0.1, blue: 0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Fixed header with close button and search bar
                VStack(spacing: 12) {
                    // Close button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Text("新規投稿")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        // Placeholder for symmetry
                        Color.clear.frame(width: 28, height: 28)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Search bar - Fixed position
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        TextField("曲名、アーティスト名で検索", text: $viewModel.searchQuery)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                        if !viewModel.searchQuery.isEmpty {
                            Button(action: { viewModel.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .background(Color.clear)
                .padding(.bottom, 8)

                // Scrollable content area
                if viewModel.isSearching {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                } else if !viewModel.searchResults.isEmpty {
                    // Search results
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.searchResults, id: \.id) { song in
                                Button(action: {
                                    Task {
                                        await viewModel.selectSong(song)
                                    }
                                }) {
                                    MusicKitSearchRow(song: song)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let selectedSong = viewModel.selectedSong {
                    // Selected song and post creation
                    ScrollView {
                    VStack(spacing: 16) {
                        // Album artwork and song info
                        HStack(spacing: 12) {
                            if let artwork = selectedSong.artwork {
                                AsyncImage(url: artwork.url(width: 80, height: 80)) { phase in
                                    switch phase {
                                    case .empty:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                    case .failure:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                    @unknown default:
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedSong.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                Text(selectedSong.artistName)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)

                        // Preview loading indicator
                        if viewModel.isFetchingPreview {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("プレビューを取得中...")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.vertical, 8)
                        }

                        // Play/Stop button
                        Button(action: {
                            if viewModel.isPlaying {
                                viewModel.stopPreview()
                            } else {
                                Task {
                                    await viewModel.playPreview()
                                }
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: viewModel.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 20))
                                Text(viewModel.isPlaying ? "停止" : "30秒プレビュー再生")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: viewModel.isPlaying ?
                                        [Color.red, Color.orange] :
                                        [Color.green, Color.blue]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                        }
                        .disabled(viewModel.isFetchingPreview)
                        .opacity(viewModel.isFetchingPreview ? 0.5 : 1.0)
                        .padding(.horizontal)

                        // Comment field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("コメント")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            TextEditor(text: $viewModel.comment)
                                .frame(height: 80)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .focused($isCommentFocused)
                                .scrollContentBackground(.hidden)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("完了") {
                                            isCommentFocused = false
                                        }
                                    }
                                }
                        }
                        .padding(.horizontal)

                        // Post button
                        Button(action: {
                            Task {
                                await viewModel.createPost()
                                if viewModel.postCreated {
                                    postCreated = true
                                    dismiss()
                                }
                            }
                        }) {
                            if viewModel.isPosting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("投稿")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                        }
                        .disabled(viewModel.isPosting || viewModel.isFetchingPreview)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .padding(.top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        Text("曲を検索して投稿を作成")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxHeight: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
            }
        }
        .navigationBarHidden(true)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct MusicKitSearchRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                AsyncImage(url: artwork.url(width: 50, height: 50)) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    @unknown default:
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(width: 50, height: 50)
                .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .foregroundColor(.white)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                if let albumTitle = song.albumTitle {
                    Text(albumTitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showEditProfile = false
    @State private var editedProfileImageUrl = ""
    @State private var editedDisplayName = ""
    @State private var isUpdating = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if let user = authManager.currentUser {
                            // User info section
                            VStack(spacing: 16) {
                                // Profile image
                                if let profileImageUrl = user.profileImageUrl, !profileImageUrl.isEmpty {
                                    AsyncImage(url: URL(string: profileImageUrl)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.white.opacity(0.15))

                                            ProgressView()
                                                .tint(.white)
                                        }
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(width: 100, height: 100)

                                        Image(systemName: "person.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }

                                VStack(spacing: 8) {
                                    Text(user.displayName)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)

                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.6))

                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            .padding(.top, 40)

                            // Action buttons
                            VStack(spacing: 16) {
                                // Edit profile button
                                Button(action: {
                                    editedProfileImageUrl = user.profileImageUrl ?? ""
                                    editedDisplayName = user.displayName
                                    showEditProfile = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 18))
                                        Text("プロフィール編集")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.3))
                                    .cornerRadius(12)
                                }

                                // Logout button
                                Button(action: {
                                    authManager.logout()
                                }) {
                                    HStack {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                            .font(.system(size: 18))
                                        Text("ログアウト")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(12)
                                }

                                // Delete account button
                                Button(action: {
                                    showDeleteConfirmation = true
                                }) {
                                    HStack {
                                        if isDeleting {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "trash")
                                                .font(.system(size: 18))
                                            Text("アカウント削除")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.3))
                                    .cornerRadius(12)
                                }
                                .disabled(isDeleting)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 32)
                        }

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("プロフィール")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "アカウントを削除しますか？",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    deleteAccount()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    profileImageUrl: $editedProfileImageUrl,
                    displayName: $editedDisplayName,
                    isUpdating: $isUpdating,
                    onSave: {
                        Task {
                            await updateProfile()
                        }
                    }
                )
                .environmentObject(authManager)
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                try await authManager.deleteAccount()
            } catch {
                // Error handled by logout in deleteAccount
            }
            isDeleting = false
        }
    }

    private func updateProfile() async {
        isUpdating = true
        do {
            let updatedUser = try await APIClient.shared.updateProfile(
                displayName: editedDisplayName.isEmpty ? nil : editedDisplayName,
                profileImageUrl: editedProfileImageUrl.isEmpty ? nil : editedProfileImageUrl,
                bio: nil
            )

            // Update currentUser with new profile information
            if let currentUser = authManager.currentUser {
                authManager.currentUser = AuthResponse(
                    token: currentUser.token,
                    userId: currentUser.userId,
                    username: currentUser.username,
                    email: currentUser.email,
                    displayName: updatedUser.displayName,
                    profileImageUrl: updatedUser.profileImageUrl
                )
            }

            showEditProfile = false
        } catch {
            print("❌ Failed to update profile: \(error)")
        }
        isUpdating = false
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Binding var profileImageUrl: String
    @Binding var displayName: String
    @Binding var isUpdating: Bool
    let onSave: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Preview of profile image
                        VStack(spacing: 12) {
                            Text("プロフィール画像プレビュー")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))

                            if !profileImageUrl.isEmpty {
                                AsyncImage(url: URL(string: profileImageUrl)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.15))

                                        ProgressView()
                                            .tint(.white)
                                    }
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                )
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 100, height: 100)

                                    Image(systemName: "person.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .padding(.top, 20)

                        // Form fields
                        VStack(spacing: 16) {
                            // Display name
                            VStack(alignment: .leading, spacing: 8) {
                                Text("表示名")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))

                                TextField("表示名", text: $displayName)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(10)
                            }

                            // Profile image URL
                            VStack(alignment: .leading, spacing: 8) {
                                Text("プロフィール画像URL")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))

                                TextField("https://example.com/image.jpg", text: $profileImageUrl)
                                    .foregroundColor(.white)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(10)

                                Text("画像のURLを入力してください")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 24)

                        // Save button
                        Button(action: {
                            onSave()
                        }) {
                            if isUpdating {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Text("保存")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        .disabled(isUpdating)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("プロフィール編集")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("キャンセル")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
