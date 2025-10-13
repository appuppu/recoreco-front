import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("アカウント作成")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 40)

                    VStack(spacing: 16) {
                        TextField("ユーザー名（英語）", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)

                        TextField("メールアドレス", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)

                        SecureField("パスワード（6文字以上）", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: signUp) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("登録")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || !isFormValid)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var isFormValid: Bool {
        !username.isEmpty && !email.isEmpty && !password.isEmpty && password.count >= 6
    }

    private func signUp() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signUp(
                    username: username,
                    email: email,
                    password: password
                )
                dismiss()
            } catch {
                errorMessage = "登録に失敗しました"
            }
            isLoading = false
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(AuthManager())
}
