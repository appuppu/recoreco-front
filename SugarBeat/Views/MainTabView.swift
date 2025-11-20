import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedTab = 0
    @State private var refreshTrigger = false
    @State private var showingCreatePost = false
    @State private var showingLoginPrompt = false
    @State private var postCreated = false
    @State private var tutorialStep: TutorialStep = .welcome
    @State private var showingInteractiveTutorial = false

    var body: some View {
        ZStack {
            // Main tab view
            TabView(selection: $selectedTab) {
                // Tab 1: Home (自分の投稿)
                FeedView(refreshTrigger: $refreshTrigger)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("ホーム")
                    }
                    .tag(0)

                // Tab 2: Following (フォロー中)
                FollowingFeedView()
                    .tabItem {
                        Image(systemName: "person.2.fill")
                        Text("フォロー中")
                    }
                    .tag(1)

                // Tab 3: Create Post (中央の+ボタン)
                Color.clear
                    .tabItem {
                        Image(systemName: "plus.circle.fill")
                        Text("")
                    }
                    .tag(2)

                // Tab 4: Notifications
                NotificationsView()
                    .tabItem {
                        Image(systemName: "bell.fill")
                        Text("通知")
                    }
                    .tag(3)

                // Tab 5: User Search
                UserSearchView()
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("検索")
                    }
                    .tag(4)
            }
            .accentColor(.orange)
            .onChange(of: selectedTab) { newValue in
                // When center tab is tapped, show create post
                if newValue == 2 {
                    if !authManager.isAuthenticated {
                        showingLoginPrompt = true
                    } else {
                        showingCreatePost = true
                    }
                    // Reset to previous tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        selectedTab = 0
                    }
                }
            }

            // Ad banner above tab bar
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    AdBannerView()
                        .frame(height: 50)
                        .background(Color.black.opacity(0.9))
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 49) // Tab bar height is ~49pt
                }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showingCreatePost) {
            refreshTrigger.toggle()
        } content: {
            CreatePostView(
                postCreated: $postCreated,
                tutorialStep: $tutorialStep,
                showingInteractiveTutorial: $showingInteractiveTutorial
            )
        }
        .sheet(isPresented: $showingLoginPrompt) {
            LoginView()
        }
    }
}

