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
        setupSessionExpirationListener()
    }

    private func setupSessionExpirationListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SessionExpired"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logout()
            }
        }
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
        let request = LoginRequest(email: email, password: password)
        let response = try await APIClient.shared.login(request: request)
        saveAuth(response: response)
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        token = nil
        currentUser = nil
        isAuthenticated = false
        APIClient.shared.clearAuthToken()
        print("🚪 User logged out")
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
