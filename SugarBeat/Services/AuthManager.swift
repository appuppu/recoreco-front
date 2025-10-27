import Foundation
import Combine

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AuthResponse?
    @Published var token: String?

    private let tokenKey = "auth_token"
    private let userKey = "current_user"

    init() {
        loadSavedAuth()
    }

    func signUp(username: String, email: String, password: String) async throws {
        let request = SignUpRequest(
            username: username,
            email: email,
            password: password
        )

        let response = try await APIClient.shared.signUp(request: request)
        saveAuth(response: response)
    }

    func login(email: String, password: String) async throws {
        print("🔵 AuthManager.login() called with email: \(email)")
        let request = LoginRequest(email: email, password: password)
        do {
            let response = try await APIClient.shared.login(request: request)
            print("✅ Login response received: userId=\(response.userId), username=\(response.username)")
            saveAuth(response: response)
        } catch {
            print("❌ AuthManager.login() error: \(error)")
            throw error
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        token = nil
        currentUser = nil
        isAuthenticated = false
    }

    func deleteAccount() async throws {
        try await APIClient.shared.deleteAccount()
        logout()
    }

    private func saveAuth(response: AuthResponse) {
        self.token = response.token
        self.currentUser = response
        self.isAuthenticated = true

        UserDefaults.standard.set(response.token, forKey: tokenKey)
        if let encoded = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(encoded, forKey: userKey)
        }

        APIClient.shared.setAuthToken(response.token)
        APIClient.shared.setCurrentUserId(response.userId)
    }

    private func loadSavedAuth() {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              let userData = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(AuthResponse.self, from: userData) else {
            return
        }

        self.token = token
        self.currentUser = user
        self.isAuthenticated = true

        APIClient.shared.setAuthToken(token)
        APIClient.shared.setCurrentUserId(user.userId)
    }
}
