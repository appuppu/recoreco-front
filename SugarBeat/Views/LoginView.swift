import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignUp = false

    var body: some View {
        ZStack {
                // Background - simple black
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Title
                    Text("ログイン")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.bottom, 40)

                    // Login Form
                    VStack(spacing: 20) {
                        VStack(spacing: 16) {
                            TextField("", text: $email, prompt: Text("メールアドレス").foregroundColor(.white.opacity(0.5)))
                                .textFieldStyle(GlassTextFieldStyle())
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)

                            SecureField("", text: $password, prompt: Text("パスワード").foregroundColor(.white.opacity(0.5)))
                                .textFieldStyle(GlassTextFieldStyle())
                                .textContentType(.password)
                        }

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                                .padding(.horizontal)
                        }

                        Button(action: login) {
                            ZStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("ログイン")
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
                            .shadow(color: Color.purple.opacity(0.5), radius: 10, x: 0, y: 5)
                        }
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)

                        Button(action: {
                            showSignUp = true
                        }) {
                            Text("アカウントを作成")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 8)

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                            Text("または")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 12)
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 20)

                        // Google Sign In Button
                        Button(action: signInWithGoogle) {
                            HStack {
                                Image(systemName: "globe")
                                    .font(.system(size: 20))
                                Text("Googleでログイン")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .cornerRadius(16)
                        }
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.6 : 1.0)

                        // Apple Sign In Button
                        SignInWithAppleButton(
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                                let appleRequest = authManager.signInWithApple()
                                request.nonce = appleRequest.nonce
                            },
                            onCompletion: { result in
                                handleAppleSignIn(result)
                            }
                        )
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 80 : 32)

                    Spacer()
                }

                // Close button (top right)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                        .padding(.top, 50)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showSignUp) {
                SignUpView()
            }
            .onChange(of: authManager.isAuthenticated) { authenticated in
                if authenticated && !authManager.needsUsernameSetup {
                    dismiss()
                }
            }
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.login(email: email, password: password)
            } catch {
                errorMessage = "ログインに失敗しました"
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let viewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "エラーが発生しました"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signInWithGoogle(presenting: viewController)
                // Don't dismiss here - onChange will handle it
            } catch {
                errorMessage = "Googleログインに失敗しました"
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                switch result {
                case .success(let authorization):
                    try await authManager.handleAppleSignInCompletion(authorization)
                    // Don't dismiss here - onChange will handle it
                case .failure(let error):
                    throw error
                }
            } catch {
                // Check if user canceled
                if let authError = error as? ASAuthorizationError {
                    switch authError.code {
                    case .canceled:
                        // Don't show error message for user cancellation
                        return
                    case .unknown:
                        errorMessage = "Appleログインの設定に問題があります。アプリの設定を確認してください。"
                    case .invalidResponse:
                        errorMessage = "Appleからの応答が無効です。"
                    case .notHandled:
                        errorMessage = "Appleログインが処理されませんでした。"
                    case .failed:
                        errorMessage = "Appleログインに失敗しました。設定を確認してください。"
                    @unknown default:
                        errorMessage = "Appleログインに失敗しました。"
                    }
                } else {
                    errorMessage = "Appleログインに失敗しました。"
                }
            }
            isLoading = false
        }
    }
}

// Custom glass-morphism text field style
struct GlassTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .font(.body)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
