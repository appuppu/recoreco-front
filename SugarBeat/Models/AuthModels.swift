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

struct AuthResponse: Codable {
    let token: String
    let userId: Int64
    let username: String
    let email: String
    let displayName: String
    let profileImageUrl: String?
    let isPublic: Bool?
}
