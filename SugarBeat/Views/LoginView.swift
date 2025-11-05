import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSignUp = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.orange.opacity(0.8),
                        Color.red.opacity(0.6),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Logo and App Name
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.orange.opacity(0.4),
                                            Color.red.opacity(0.3)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                                .blur(radius: 20)

                            Image("DiscoveryIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        }

                        Text("レコレコ")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white,
                                        Color.white.opacity(0.9)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("おすすめの音楽を紹介しよう！")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 60)

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
                                        Color.orange,
                                        Color.red
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color.orange.opacity(0.5), radius: 10, x: 0, y: 5)
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
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 80 : 32)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSignUp) {
                SignUpView()
            }
        }
        .navigationViewStyle(.stack)
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
