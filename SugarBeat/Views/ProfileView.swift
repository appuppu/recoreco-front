import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSettings = false
    @State private var editingChannel: Channel?
    @State private var selectedChannelId: String?
    @EnvironmentObject var authManager: AuthManager
    @Binding var selectedTab: Int
    @State private var profileTab: ProfileTab = .posts

    enum ProfileTab {
        case posts
        case sharedChannels
        case personalChannels
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            } else if let user = viewModel.currentUser {
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Header
                        VStack(spacing: 12) {
                            // Profile Image
                            if let imageUrl = user.profileImageUrl {
                                AsyncImage(url: URL(string: imageUrl)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Image("recoreco")
                                        .resizable()
                                        .scaledToFill()
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                            } else {
                                Image("recoreco")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            }

                            // Display Name
                            Text(user.username)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)

                            // Bio
                            if let bio = user.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                        }
                        .padding(.top, 16)

                        // Tab switcher
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation {
                                    profileTab = .posts
                                }
                            }) {
                                Text("投稿")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(profileTab == .posts ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(profileTab == .posts ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                                    .cornerRadius(8)
                            }

                            Button(action: {
                                withAnimation {
                                    profileTab = .sharedChannels
                                }
                                if viewModel.channels.isEmpty {
                                    Task {
                                        await viewModel.loadChannels()
                                    }
                                }
                            }) {
                                Text("参加中")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(profileTab == .sharedChannels ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(profileTab == .sharedChannels ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                                    .cornerRadius(8)
                            }

                            Button(action: {
                                withAnimation {
                                    profileTab = .personalChannels
                                }
                                if viewModel.channels.isEmpty {
                                    Task {
                                        await viewModel.loadChannels()
                                    }
                                }
                            }) {
                                Text("個人")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(profileTab == .personalChannels ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(profileTab == .personalChannels ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)

                        // Content
                        if profileTab == .posts {
                            postsContent
                        } else if profileTab == .sharedChannels {
                            channelsContent(channelType: .shared)
                        } else {
                            channelsContent(channelType: .personal)
                        }
                    }
                }
            } else {
                Text("プロフィールの読み込みに失敗しました")
                    .foregroundColor(.white)
            }
        }
        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            if #available(iOS 16.4, *) {
                SettingsView()
                    .presentationBackground(Color.clear)
                    .background(Color.black)
            } else {
                SettingsView()
                    .background(Color.black)
            }
        }
        .sheet(item: $editingChannel) { channel in
            if #available(iOS 16.4, *) {
                EditChannelView(channel: channel, onUpdate: {
                    Task {
                        await viewModel.loadChannels()
                    }
                })
                .presentationBackground(Color.clear)
                .background(Color.black)
            } else {
                EditChannelView(channel: channel, onUpdate: {
                    Task {
                        await viewModel.loadChannels()
                    }
                })
                .background(Color.black)
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedChannelId != nil },
            set: { if !$0 { selectedChannelId = nil } }
        )) {
            if let channelId = selectedChannelId {
                if #available(iOS 16.4, *) {
                    ChannelDetailView(channelId: channelId)
                        .presentationBackground(Color.clear)
                        .background(Color.black)
                } else {
                    ChannelDetailView(channelId: channelId)
                        .background(Color.black)
                }
            }
        }
        .task {
            await viewModel.loadCurrentUser()
            await viewModel.loadChannels()
            await viewModel.loadPosts()
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var postsContent: some View {
        if viewModel.isLoadingPosts {
            HStack {
                ProgressView()
                    .tint(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if viewModel.posts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.4))
                Text("まだ投稿がありません")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                Button(action: {
                    selectedTab = 2
                }) {
                    Text("投稿する")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            PostGridView(
                posts: viewModel.posts,
                showingLoginPrompt: .constant(false),
                showUserInfo: false,
                isLoading: viewModel.isLoadingPosts,
                onRefresh: {
                    await viewModel.loadPosts()
                }
            )
        }
    }

    @ViewBuilder
    private func channelsContent(channelType: ChannelType) -> some View {
        let filteredChannels = viewModel.channels.filter { $0.channelType == channelType }

        if viewModel.isLoadingChannels {
            HStack {
                ProgressView()
                    .tint(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if filteredChannels.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.4))
                Text(channelType == .shared ? "参加中の公開チャンネルはありません" : "個人チャンネルがありません")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                Button(action: {
                    selectedTab = 2
                }) {
                    Text("投稿する")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredChannels) { channel in
                    ChannelListRow(
                        channel: channel,
                        onTap: {
                            selectedChannelId = channel.id
                        },
                        onEdit: channelType == .personal ? {
                            editingChannel = channel
                        } : nil,
                        onDelete: channelType == .personal ? {
                            Task {
                                if let channelId = channel.id {
                                    await viewModel.deleteChannel(channelId: channelId)
                                }
                            }
                        } : nil
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
    }
}

// MARK: - Channel Card
struct ChannelCard: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Channel thumbnail
            if let artworkUrl = channel.latestPostArtworkUrl,
               let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 140, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 140, height: 140)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }

            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Channel type icon
                    Image(systemName: channel.channelType == .shared ? "globe" : "person.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    Text(channel.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(channel.followerCount ?? 0)")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(width: 140)
    }
}

// MARK: - Channel List Row
struct ChannelListRow: View {
    let channel: Channel
    let onTap: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
            // Channel artwork
            if let artworkUrl = channel.latestPostArtworkUrl,
               let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }

            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Text(channel.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(channel.followerCount ?? 0)")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Edit button (only show if onEdit is provided)
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Delete button (only show if onDelete is provided)
            if onDelete != nil {
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .alert("チャンネルを削除", isPresented: $showingDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("このチャンネルを削除してもよろしいですか？チャンネル内のすべての投稿も削除されます。この操作は取り消せません。")
        }
    }
}

// MARK: - Edit Channel View
struct EditChannelView: View {
    let channel: Channel
    let onUpdate: () -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: EditChannelViewModel

    init(channel: Channel, onUpdate: @escaping () -> Void) {
        self.channel = channel
        self.onUpdate = onUpdate
        _viewModel = StateObject(wrappedValue: EditChannelViewModel(channel: channel))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("チャンネル名を編集")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top, 32)

                    TextField("チャンネル名", text: $viewModel.channelName)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            await viewModel.updateChannel()
                            if viewModel.channelUpdated {
                                onUpdate()
                                dismiss()
                            }
                        }
                    }) {
                        if viewModel.isUpdating {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("保存")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                    .disabled(viewModel.isUpdating || viewModel.channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((viewModel.isUpdating || viewModel.channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("チャンネル編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Edit Channel ViewModel
@MainActor
class EditChannelViewModel: ObservableObject {
    @Published var channelName: String
    @Published var isUpdating = false
    @Published var channelUpdated = false
    @Published var errorMessage: String?

    private let channel: Channel

    init(channel: Channel) {
        self.channel = channel
        self.channelName = channel.name
    }

    func updateChannel() async {
        let trimmedName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "チャンネル名を入力してください"
            return
        }

        guard let channelId = channel.id else {
            errorMessage = "チャンネルIDが見つかりません"
            return
        }

        isUpdating = true
        errorMessage = nil

        do {
            try await FirestoreChannelManager.shared.updateChannel(channelId: channelId, name: trimmedName)
            channelUpdated = true
            print("✅ Channel updated successfully")
        } catch {
            print("❌ Failed to update channel: \(error)")
            errorMessage = "チャンネルの更新に失敗しました"
        }

        isUpdating = false
    }
}

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var channels: [Channel] = []
    @Published var isLoadingChannels = false
    @Published var posts: [Post] = []
    @Published var isLoadingPosts = false

    func loadCurrentUser() async {
        isLoading = true

        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                print("❌ No current user ID")
                isLoading = false
                return
            }

            currentUser = try await FirestoreUserManager.shared.getUser(userId: currentUserId)
            print("✅ Loaded current user: \(currentUser?.username ?? "")")
        } catch {
            print("❌ Failed to load current user: \(error)")
        }

        isLoading = false
    }

    func loadPosts() async {
        isLoadingPosts = true

        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                isLoadingPosts = false
                return
            }

            let (fetchedPosts, _) = try await FirestorePostManager.shared.getUserPosts(userId: currentUserId)
            posts = fetchedPosts
            print("✅ Loaded \(posts.count) posts")
        } catch {
            print("❌ Failed to load posts: \(error)")
        }

        isLoadingPosts = false
    }

    func loadChannels() async {
        isLoadingChannels = true

        do {
            guard let currentUserId = Auth.auth().currentUser?.uid else {
                isLoadingChannels = false
                return
            }

            // Get followed channels
            var followedChannels = try await FirestoreChannelManager.shared.getFollowedChannels(userId: currentUserId)

            // Get own channels
            let ownChannels = try await FirestoreChannelManager.shared.getUserChannels(userId: currentUserId)

            // Merge and remove duplicates
            for ownChannel in ownChannels {
                if !followedChannels.contains(where: { $0.id == ownChannel.id }) {
                    followedChannels.append(ownChannel)
                }
            }

            // Sort by latest post date
            channels = followedChannels.sorted { ($0.latestPostAt ?? Date.distantPast) > ($1.latestPostAt ?? Date.distantPast) }
            print("✅ Loaded \(channels.count) channels")
        } catch {
            print("❌ Failed to load channels: \(error)")
        }

        isLoadingChannels = false
    }

    func deleteChannel(channelId: String) async {
        do {
            try await FirestoreChannelManager.shared.deleteChannel(channelId: channelId)
            await loadChannels() // Reload channels
        } catch {
            print("❌ Failed to delete channel: \(error)")
        }
    }
}
