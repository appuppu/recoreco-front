import Foundation

struct SignUpRequest: Codable {
    let username: String
    let email: String
    let password: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct GoogleAuthRequest: Codable {
    let idToken: String
    let username: String?
}

struct AppleAuthRequest: Codable {
    let identityToken: String
    let authorizationCode: String
    let username: String?
    let email: String?
}

struct AuthResponse: Codable {
    let token: String
    let userId: String  // Changed from Int64 to String for Firebase UID compatibility
    let username: String
    let email: String
    let displayName: String
    let profileImageUrl: String?
}
