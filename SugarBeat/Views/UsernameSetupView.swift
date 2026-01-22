import SwiftUI

struct UsernameSetupView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isUsernameAvailable: Bool?
    @State private var isCheckingUsername = false

    let email: String?

    var body: some View {
        ZStack {
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

            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Text("プロフィール設定")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("ユーザー名を設定してください")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 60)

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("", text: $username, prompt: Text("ユーザー名 (例: tanaka_taro)").foregroundColor(.white.opacity(0.5)))
                                .textFieldStyle(GlassTextFieldStyle())
                                .autocapitalization(.none)
                                .onChange(of: username) { _ in
                                    checkUsernameAvailability()
                                }

                            if isCheckingUsername {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 12)
                            } else if let available = isUsernameAvailable {
                                Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(available ? .green : .red)
                                    .padding(.trailing, 12)
                            }
                        }

                        Text("半角英数字、アンダースコア、ハイフンが使用できます")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                    }

                    if let email = email {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.white.opacity(0.6))
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal)
                    }

                    Button(action: completeSetup) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("完了")
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
                    .disabled(!isValidInput || isLoading)
                    .opacity(!isValidInput || isLoading ? 0.6 : 1.0)
                }
                .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 80 : 32)

                Spacer()
            }
        }
        .interactiveDismissDisabled()
    }

    private var isValidInput: Bool {
        !username.isEmpty &&
        isUsernameValid(username) &&
        isUsernameAvailable == true
    }

    private func isUsernameValid(_ username: String) -> Bool {
        let pattern = "^[a-zA-Z0-9_-]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: username)
    }

    private func checkUsernameAvailability() {
        guard isUsernameValid(username) else {
            isUsernameAvailable = nil
            return
        }

        isCheckingUsername = true

        Task {
            do {
                let available = try await FirestoreUserManager.shared.checkUsernameAvailability(username: username)
                await MainActor.run {
                    isUsernameAvailable = available
                    isCheckingUsername = false
                }
            } catch {
                await MainActor.run {
                    isUsernameAvailable = nil
                    isCheckingUsername = false
                }
            }
        }
    }

    private func completeSetup() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.completeUserSetup(username: username, displayName: username)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "設定に失敗しました: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    UsernameSetupView(email: "test@example.com")
        .environmentObject(AuthManager())
}
