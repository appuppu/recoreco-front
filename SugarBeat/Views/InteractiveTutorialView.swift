import SwiftUI

// チュートリアルのステップを管理
enum TutorialStep: Int {
    case welcome = 0
    case tapCreateButton = 1
    case searchSong = 2
    case selectSong = 3
    case tapPostButton = 4
    case completed = 5
}

struct InteractiveTutorialView: View {
    @Binding var isPresented: Bool
    @Binding var currentStep: TutorialStep
    let targetFrame: CGRect?
    let onNext: () -> Void
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            // 暗いオーバーレイ（ハイライト部分以外）
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .allowsHitTesting(false)  // タッチを透過
                .overlay(
                    GeometryReader { geometry in
                        if let frame = targetFrame {
                            // ハイライト部分を切り抜く
                            HighlightCutout(targetFrame: frame)
                                .allowsHitTesting(false)  // タッチを透過
                        }
                    }
                )

            // 説明テキストとボタン
            VStack {
                // 全てのステップで上に配置（バナー広告対応）
                InstructionCard(
                    step: currentStep,
                    onNext: {
                        guard !isProcessing else { return }
                        isProcessing = true
                        onNext()
                        // 0.5秒後にリセット（アニメーション完了を待つ）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isProcessing = false
                        }
                    },
                    onSkip: {
                        guard !isProcessing else { return }
                        isProcessing = true
                        isPresented = false
                        UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
                    },
                    isProcessing: isProcessing
                )
                .padding(.horizontal, 20)
                .padding(.top, 180)

                Spacer()
            }
            .allowsHitTesting(true)  // 説明カードだけタッチ可能
        }
    }
}

// ハイライト部分を切り抜くビュー
struct HighlightCutout: View {
    let targetFrame: CGRect

    var body: some View {
        ZStack {
            // 全体を暗くする
            Rectangle()
                .fill(Color.clear)

            // ハイライト部分を明るくする（リング効果）
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: targetFrame.width + 40, height: targetFrame.height + 20)
                .position(
                    x: targetFrame.midX,
                    y: targetFrame.midY
                )
                .shadow(color: .white.opacity(0.5), radius: 10)
        }
    }
}

// 説明カード
struct InstructionCard: View {
    let step: TutorialStep
    let onNext: () -> Void
    let onSkip: () -> Void
    let isProcessing: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 16) {
                // アイコン
                Image(systemName: stepIcon)
                    .font(.system(size: 40))
                    .foregroundColor(.white)

                // タイトル
                Text(stepTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // 説明
                Text(stepDescription)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // ボタン
                HStack(spacing: 12) {
                    // スキップボタン（welcomeとcompletedとtapCreateButton以外）
                    if step != .welcome && step != .completed && step != .tapCreateButton && step != .searchSong && step != .selectSong && step != .tapPostButton {
                        Button(action: onSkip) {
                            Text("スキップ")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }

                    // welcomeとcompletedのみボタンを表示
                    if step == .welcome || step == .completed {
                        Button(action: onNext) {
                            Text(buttonText)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing)
                        .opacity(isProcessing ? 0.5 : 1.0)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.25))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            )

            // バツボタン（右上）
            Button(action: {
                guard !isProcessing else { return }
                onSkip()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(12)
        }
    }

    private var stepIcon: String {
        switch step {
        case .welcome:
            return "hand.wave.fill"
        case .tapCreateButton:
            return "plus.circle.fill"
        case .searchSong:
            return "magnifyingglass"
        case .selectSong:
            return "music.note"
        case .tapPostButton:
            return "checkmark.circle.fill"
        case .completed:
            return "party.popper.fill"
        }
    }

    private var stepTitle: String {
        switch step {
        case .welcome:
            return "最初のおすすめ音楽を紹介しよう！"
        case .tapCreateButton:
            return "おすすめの音楽紹介をタップ"
        case .searchSong:
            return "おすすめの曲を検索"
        case .selectSong:
            return "曲を選択"
        case .tapPostButton:
            return "紹介ボタンをタップ"
        case .completed:
            return "完了！🎉"
        }
    }

    private var stepDescription: String {
        switch step {
        case .welcome:
            return "一緒に最初のおすすめ音楽を紹介してみましょう。\nステップごとにガイドします。"
        case .tapCreateButton:
            return "左下の「＋」ボタンをタップして、\nおすすめの音楽紹介を始めましょう。"
        case .searchSong:
            return "検索バーに曲名やアーティスト名を入力して、\n検索ボタンをタップして曲を探しましょう。"
        case .selectSong:
            return "検索結果からおすすめの曲をタップして選択してください。"
        case .tapPostButton:
            return "準備ができたら「この内容で紹介する」ボタンをタップして、\n最初のおすすめ音楽を完成させましょう！"
        case .completed:
            return "素晴らしい！最初のおすすめ音楽が完成しました。\nこれからたくさんの音楽をシェアして楽しみましょう！"
        }
    }

    private var buttonText: String {
        switch step {
        case .welcome:
            return "始める"
        case .searchSong, .selectSong, .tapPostButton:
            return "次へ"
        case .completed:
            return "完了"
        case .tapCreateButton:
            return ""
        }
    }
}

// PreferenceKeyでボタンの位置を取得
struct ButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// ボタンフレーム取得用のViewModifier
struct FrameGetter: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ButtonFramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                }
            )
            .onPreferenceChange(ButtonFramePreferenceKey.self) { value in
                self.frame = value
            }
    }
}

extension View {
    func captureFrame(in frame: Binding<CGRect>) -> some View {
        modifier(FrameGetter(frame: frame))
    }
}

#Preview {
    InteractiveTutorialView(
        isPresented: .constant(true),
        currentStep: .constant(.welcome),
        targetFrame: CGRect(x: 300, y: 700, width: 60, height: 60),
        onNext: {}
    )
}
