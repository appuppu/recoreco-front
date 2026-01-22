import SwiftUI
import FirebaseAuth

struct ReportPostView: View {
    let post: Post
    @Environment(\.dismiss) var dismiss
    @State private var selectedReason = "不適切なコンテンツ"
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    let reasons = [
        "不適切なコンテンツ",
        "スパム",
        "嫌がらせ",
        "虚偽の情報",
        "その他"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("報告理由")) {
                    Picker("理由", selection: $selectedReason) {
                        ForEach(reasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("詳細（任意）")) {
                    TextEditor(text: $description)
                        .frame(height: 100)
                }

                Section {
                    Button(action: {
                        Task {
                            await submitReport()
                        }
                    }) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("報告を送信")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("紹介を報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("報告完了", isPresented: $showingSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("紹介を報告しました")
        }
        .alert("エラー", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func submitReport() async {
        isSubmitting = true

        do {
            guard let postId = post.id else {
                errorMessage = "Invalid post ID"
                isSubmitting = false
                return
            }
            try await FirestoreReportManager.shared.reportPost(
                postId: postId,
                reason: selectedReason,
                description: description.isEmpty ? nil : description
            )
            isSubmitting = false
            showingSuccessAlert = true
        } catch {
            print("❌ Failed to report post: \(error)")
            isSubmitting = false
            errorMessage = "報告の送信に失敗しました。もう一度お試しください。"
            showingErrorAlert = true
        }
    }
}
