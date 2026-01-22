import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "music.note.house.fill",
            title: "チャンネルで音楽を紹介",
            description: "チャンネルを作成して、テーマに沿った音楽を投稿できます。\n好きなジャンルやムードのチャンネルを作りましょう。",
            gradient: [Color.purple, Color.blue]
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "チャンネルをフォロー",
            description: "気になるチャンネルをフォローすると、「フォロー中」タブで最新の投稿をチェックできます。\n自分のチャンネルも作成して投稿しましょう。",
            gradient: [Color.blue, Color.cyan]
        ),
        OnboardingPage(
            icon: "safari",
            title: "すべてのチャンネルを探索",
            description: "「すべて」タブでは、全ユーザーのチャンネルを探索できます。\n投稿が新しい順に表示されるので、トレンドをチェック！",
            gradient: [Color.cyan, Color.green]
        ),
        OnboardingPage(
            icon: "music.note",
            title: "音楽を投稿して楽しむ",
            description: "チャンネルに音楽を投稿して、おすすめの曲をシェアしましょう。\n30秒のプレビューと一緒にコメントを添えられます。",
            gradient: [Color.green, Color.yellow]
        )
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: pages[currentPage].gradient),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                    }) {
                        Text("スキップ")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal, 20)

                Spacer()

                // Content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Spacer()

                // Bottom button
                if currentPage == pages.count - 1 {
                    Button(action: {
                        withAnimation {
                            dismiss()
                            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        }
                    }) {
                        Text("始める")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.2)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                            )
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 80 : 40)
                    .padding(.bottom, 50)
                    .transition(.opacity)
                } else {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        HStack(spacing: 8) {
                            Text("次へ")
                                .font(.system(size: 18, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.2)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 80 : 40)
                    .padding(.bottom, 50)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let gradient: [Color]
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 30) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)

                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            .padding(.top, 40)

            // Title
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Description
            Text(page.description)
                .font(.system(size: 17))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.vertical, 20)
    }
}

#Preview {
    OnboardingView()
}
