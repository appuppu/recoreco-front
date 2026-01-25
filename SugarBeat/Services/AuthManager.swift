import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var needsUsernameSetup = false
    @Published var pendingUserEmail: String?

    private let userIdKey = "current_user_id"

    // Apple Sign In
    private var currentNonce: String?

    init() {
        // CRITICAL: Ensure Firebase is configured BEFORE accessing Auth
        FirebaseConfig.ensureConfigured()

        loadSavedAuth()
        setupFirebaseAuthListener()
    }

    private func setupFirebaseAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                if let firebaseUser = user {
                    await self?.loadUserFromFirestore(uid: firebaseUser.uid)
                } else {
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                }
            }
        }
    }

    private func loadUserFromFirestore(uid: String) async {
        do {
            let user = try await FirestoreUserManager.shared.getUser(userId: uid)
            self.currentUser = user
            self.isAuthenticated = true
            self.needsUsernameSetup = false
            UserDefaults.standard.set(uid, forKey: userIdKey)
            print("✅ User loaded from Firestore: \(user.username)")
        } catch {
            // User doesn't exist in Firestore, needs setup
            print("⚠️ User not found in Firestore, needs setup")
            self.isAuthenticated = false
            self.currentUser = nil
            self.needsUsernameSetup = true
            if let email = Auth.auth().currentUser?.email {
                self.pendingUserEmail = email
            }
        }
    }

    func signUp(username: String, email: String, password: String) async throws {
        // Create Firebase Auth user
        let authResult = try await Auth.auth().createUser(withEmail: email, password: password)

        // Create Firestore user document
        let user = User(
            id: authResult.user.uid,
            username: username,
            email: email,
            displayName: username
        )

        try await FirestoreUserManager.shared.createUser(user)

        // Update local state
        self.currentUser = user
        self.isAuthenticated = true
        UserDefaults.standard.set(authResult.user.uid, forKey: userIdKey)
    }

    func login(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
        // Firebase auth listener will handle the rest
    }

    func logout() {
        do {
            try Auth.auth().signOut()
            UserDefaults.standard.removeObject(forKey: userIdKey)
            currentUser = nil
            isAuthenticated = false
            print("🚪 User logged out")
        } catch {
            print("⚠️ Error signing out: \(error)")
        }
    }

    func deleteAccount() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Delete Firestore user document
        try await FirestoreUserManager.shared.deleteUser(userId: uid)

        // Delete Firebase Auth user
        try await Auth.auth().currentUser?.delete()

        logout()
    }

    func completeUserSetup(username: String, displayName: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let email = Auth.auth().currentUser?.email

        let user = User(
            id: uid,
            username: username,
            email: email,
            displayName: displayName
        )

        try await FirestoreUserManager.shared.createUser(user)

        self.currentUser = user
        self.isAuthenticated = true
        self.needsUsernameSetup = false
        self.pendingUserEmail = nil
        UserDefaults.standard.set(uid, forKey: userIdKey)

        print("✅ User setup completed: \(username)")
    }

    // MARK: - Google Sign In

    func signInWithGoogle(presenting viewController: UIViewController) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase client ID not found"])
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
        let googleUser = result.user

        guard let idToken = googleUser.idToken?.tokenString else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
        }

        let accessToken = googleUser.accessToken.tokenString

        // Sign in to Firebase with Google credentials
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let authResult = try await Auth.auth().signIn(with: credential)
        let uid = authResult.user.uid

        // Firebase auth listener will handle loading user from Firestore
        // If user doesn't exist, needsUsernameSetup will be set to true
    }

    // MARK: - Apple Sign In

    func signInWithApple() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        return request
    }

    func handleAppleSignInCompletion(_ authorization: ASAuthorization) async throws {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple ID credential"])
        }

        guard let nonce = currentNonce else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid state: nonce is missing"])
        }

        guard let appleIDToken = appleIDCredential.identityToken else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"])
        }

        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to serialize token string from data"])
        }

        // Sign in to Firebase with Apple credentials
        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idTokenString,
            rawNonce: nonce
        )

        try await Auth.auth().signIn(with: credential)

        // Firebase auth listener will handle loading user from Firestore
        // If user doesn't exist, needsUsernameSetup will be set to true
    }

    // MARK: - Helper Methods

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }

    private func loadSavedAuth() {
        // Check if there's a saved user ID (for debugging/logging purposes)
        if let userId = UserDefaults.standard.string(forKey: userIdKey) {
            print("📱 Saved user ID found: \(userId)")
        }

        // Firebase Auth handles persistence automatically
        // The auth state listener will restore the session if valid
        if let currentUser = Auth.auth().currentUser {
            print("✅ Firebase session restored for user: \(currentUser.uid)")
        }
    }
}
