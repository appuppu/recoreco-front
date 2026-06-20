import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSettings = false
    @State private var showingCompose42 = false
    @EnvironmentObject var authManager: AuthManager
    @Binding var selectedTab: Int

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

                            // "私を構成する42枚" button
                            Button {
                                showingCompose42 = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("私を構成する42枚")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [Color.purple, Color.pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(20)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.top, 16)

                        // Posts section
                        postsContent
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
        .fullScreenCover(isPresented: $showingCompose42) {
            Compose42View()
                .environmentObject(authManager)
        }
        .task {
            await viewModel.loadCurrentUser()
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
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.purple, Color.pink]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
}

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
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
}
