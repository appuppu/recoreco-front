import SwiftUI
import AuthenticationServices
import FirebaseAuth

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingUrlConfirmation = false
    @State private var urlToOpen: URL?
    @State private var urlTitle: String = ""
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var agreedToTerms = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background - flowing artwork grid
                FlowingArtworkBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Logo
                        VStack(spacing: 16) {
                            Text("アカウント作成")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("おすすめの音楽を投稿しよう")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 30)

                        // Sign Up Form
                        VStack(spacing: 20) {
                            // Agreement checkbox (moved to top)
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Button(action: {
                                        agreedToTerms.toggle()
                                    }) {
                                        Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 24))
                                            .foregroundColor(agreedToTerms ? .orange : .white.opacity(0.6))
                                    }

                                    Text("利用規約とプライバシーポリシーに同意する")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.8))
                                }

                                // Terms and Privacy links
                                HStack(spacing: 20) {
                                    Button(action: {
                                        urlTitle = "利用規約"
                                        urlToOpen = URL(string: "https://appuppu.github.io/docs/terms.html")
                                        showingUrlConfirmation = true
                                    }) {
                                        Text("利用規約")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.8))
                                            .underline()
                                    }

                                    Text("・")
                                        .foregroundColor(.white.opacity(0.5))

                                    Button(action: {
                                        urlTitle = "プライバシーポリシー"
                                        urlToOpen = URL(string: "https://appuppu.github.io/docs/privacy.html")
                                        showingUrlConfirmation = true
                                    }) {
                                        Text("プライバシーポリシー")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.8))
                                            .underline()
                                    }
                                }
                            }
                            .padding(.bottom, 20)

                            // Show form only after agreeing to terms
                            if agreedToTerms {
                                VStack(spacing: 16) {
                                    // Username field with validation indicator
                                    HStack(spacing: 8) {
                                    TextField("", text: $username, prompt: Text("ユーザー名（英数字._ 10文字以内）").foregroundColor(.white.opacity(0.5)))
                                        .textFieldStyle(GlassTextFieldStyle())
                                        .autocapitalization(.none)
                                        .onChange(of: username) { newValue in
                                            // Allow only alphanumeric characters, dots, and underscores
                                            let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
                                            if filtered != newValue {
                                                username = filtered
                                            }

                                            // Cancel previous check
                                            usernameCheckTask?.cancel()
                                            usernameAvailable = nil

                                            // Check username availability after user stops typing
                                            guard !filtered.isEmpty else { return }

                                            usernameCheckTask = Task {
                                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second debounce
                                                guard !Task.isCancelled else { return }

                                                await checkUsernameAvailability(filtered)
                                            }
                                        }

                                    // Validation indicator
                                    if isCheckingUsername {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(width: 20, height: 20)
                                    } else if let available = usernameAvailable {
                                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(available ? .green : .red)
                                    }
                                }
                                .padding(.trailing, 8)

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
                                .shadow(color: Color.purple.opacity(0.5), radius: 10, x: 0, y: 5)
                            }
                                .disabled(isLoading || !isFormValid)
                                .opacity((isLoading || !isFormValid) ? 0.6 : 1.0)

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
                                        Text("Googleで登録")
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
                        }
                        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 80 : 32)
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
            .alert("外部サイトへ移動", isPresented: $showingUrlConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("移動する") {
                    if let url = urlToOpen {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                if let url = urlToOpen {
                    Text("\(urlTitle)のページに移動します。\n\n\(url.absoluteString)")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: authManager.needsUsernameSetup) { needsSetup in
            // When username setup is completed, dismiss signup view
            if authManager.isAuthenticated && !needsSetup {
                dismiss()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { authManager.needsUsernameSetup },
            set: { _ in }
        )) {
            UsernameSetupView(email: authManager.pendingUserEmail)
                .environmentObject(authManager)
        }
    }

    private var isFormValid: Bool {
        !username.isEmpty && !email.isEmpty && !password.isEmpty && password.count >= 8 && username.count <= 10 && usernameAvailable == true && agreedToTerms
    }

    private func signUp() {
        // Validate before submitting
        if username.count > 10 {
            errorMessage = "ユーザー名は10文字以内で入力してください"
            return
        }

        // Check if username contains only allowed characters (alphanumeric, dot, underscore)
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        if username.unicodeScalars.contains(where: { !allowedCharacterSet.contains($0) }) {
            errorMessage = "ユーザー名は英数字、ピリオド、アンダースコアのみで入力してください"
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
                // Parse Firebase Auth errors
                if let authError = error as NSError?, authError.domain == "FIRAuthErrorDomain" {
                    errorMessage = translateFirebaseAuthError(authError)
                } else if let apiError = error as? APIError {
                    errorMessage = apiError.localizedDescription
                } else {
                    errorMessage = "登録に失敗しました"
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

    private func checkUsernameAvailability(_ username: String) async {
        isCheckingUsername = true
        defer { isCheckingUsername = false }

        do {
            let available = try await FirestoreUserManager.shared.checkUsernameAvailability(username: username)
            await MainActor.run {
                usernameAvailable = available
            }
        } catch {
            await MainActor.run {
                usernameAvailable = nil
            }
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
                // If needsUsernameSetup is true, don't dismiss (UsernameSetupView will be shown)
                if !authManager.needsUsernameSetup {
                    dismiss()
                }
            } catch {
                errorMessage = "Google登録に失敗しました"
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
                    // If needsUsernameSetup is true, don't dismiss (UsernameSetupView will be shown)
                    if !authManager.needsUsernameSetup {
                        dismiss()
                    }
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
                        errorMessage = "Apple登録の設定に問題があります。アプリの設定を確認してください。"
                    case .invalidResponse:
                        errorMessage = "Appleからの応答が無効です。"
                    case .notHandled:
                        errorMessage = "Apple登録が処理されませんでした。"
                    case .failed:
                        errorMessage = "Apple登録に失敗しました。設定を確認してください。"
                    @unknown default:
                        errorMessage = "Apple登録に失敗しました。"
                    }
                } else {
                    errorMessage = "Apple登録に失敗しました。"
                }
            }
            isLoading = false
        }
    }

    private func translateFirebaseAuthError(_ error: NSError) -> String {
        guard let errorCode = AuthErrorCode(_bridgedNSError: error) else {
            return "登録に失敗しました"
        }

        switch errorCode.code {
        case .emailAlreadyInUse:
            return "このメールアドレスは既に使用されています"
        case .invalidEmail:
            return "無効なメールアドレスです"
        case .weakPassword:
            return "パスワードが弱すぎます。8文字以上で入力してください"
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .operationNotAllowed:
            return "この操作は許可されていません"
        default:
            return "登録に失敗しました"
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(AuthManager())
}
