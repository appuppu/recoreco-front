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
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Logo
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.purple.opacity(0.3),
                                                Color.blue.opacity(0.3)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .blur(radius: 20)

                                Image(systemName: "music.note.list")
                                    .font(.system(size: 50, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white,
                                                Color.white.opacity(0.8)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }

                            Text("アカウント作成")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("レコレコで音楽の記録を始めよう")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 40)

                        // Sign Up Form
                        VStack(spacing: 20) {
                            VStack(spacing: 16) {
                                TextField("", text: $username, prompt: Text("ユーザー名（英数字10文字以内）").foregroundColor(.white.opacity(0.5)))
                                    .textFieldStyle(GlassTextFieldStyle())
                                    .autocapitalization(.none)
                                    .onChange(of: username) { newValue in
                                        // Allow only alphanumeric characters
                                        let filtered = newValue.filter { $0.isLetter || $0.isNumber }
                                        if filtered != newValue {
                                            username = filtered
                                        }
                                    }

                                TextField("", text: $email, prompt: Text("メールアドレス").foregroundColor(.white.opacity(0.5)))
                                    .textFieldStyle(GlassTextFieldStyle())
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)

                                SecureField("", text: $password, prompt: Text("パスワード（8文字以上）").foregroundColor(.white.opacity(0.5)))
                                    .textFieldStyle(GlassTextFieldStyle())
                                    .textContentType(.newPassword)
                            }

                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(.horizontal)
                            }

                            Button(action: signUp) {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("登録")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.purple,
                                            Color.blue
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.purple.opacity(0.3), radius: 10, x: 0, y: 5)
                            }
                            .disabled(isLoading || !isFormValid)
                            .opacity((isLoading || !isFormValid) ? 0.6 : 1.0)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("戻る")
                                .font(.body)
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private var isFormValid: Bool {
        !username.isEmpty && !email.isEmpty && !password.isEmpty && password.count >= 8 && username.count <= 10
    }

    private func signUp() {
        // Validate before submitting
        if username.count > 10 {
            errorMessage = "ユーザー名は10文字以内で入力してください"
            return
        }

        // Check if username contains only alphanumeric characters
        let alphanumericSet = CharacterSet.alphanumerics
        if username.unicodeScalars.contains(where: { !alphanumericSet.contains($0) }) {
            errorMessage = "ユーザー名は英数字のみで入力してください"
            return
        }

        if password.count < 8 {
            errorMessage = "パスワードは8文字以上で入力してください"
            return
        }

        // Validate email format
        if !isValidEmail(email) {
            errorMessage = "有効なメールアドレスを入力してください"
            return
        }

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
                // Parse error message from backend if available
                if let apiError = error as? APIError {
                    switch apiError {
                    case .invalidResponse(_, let data):
                        if let data = data, let errorString = String(data: data, encoding: .utf8) {
                            errorMessage = errorString
                        } else {
                            errorMessage = "登録に失敗しました"
                        }
                    default:
                        errorMessage = "登録に失敗しました"
                    }
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        // Email validation regex
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

#Preview {
    SignUpView()
        .environmentObject(AuthManager())
}
