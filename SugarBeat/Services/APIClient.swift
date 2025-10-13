import Foundation

enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(Error)
    case unauthorized
}

class APIClient {
    static let shared = APIClient()

    private let baseURL = "http://192.168.0.3:8080/api"
    private var authToken: String?
    private(set) var currentUserId: Int64?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()

        // Custom date decoding to handle LocalDateTime format from Spring Boot
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatters = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss"
            ]

            for format in formatters {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Date string does not match expected formats: \(dateString)"
                )
            )
        }
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    func setAuthToken(_ token: String) {
        self.authToken = token
    }

    func setCurrentUserId(_ userId: Int64) {
        self.currentUserId = userId
    }

    // MARK: - Auth Endpoints

    func signUp(request: SignUpRequest) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/signup")!
        return try await performRequest(url: url, method: "POST", body: request, requiresAuth: false)
    }

    func login(request: LoginRequest) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/login")!
        return try await performRequest(url: url, method: "POST", body: request, requiresAuth: false)
    }

    func deleteAccount() async throws {
        let url = URL(string: "\(baseURL)/auth/account")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - User Endpoints

    func searchUsers(query: String) async throws -> [User] {
        let url = URL(string: "\(baseURL)/users/search?query=\(query)")!
        return try await performRequest(url: url, method: "GET")
    }

    func getUser(id: Int64) async throws -> User {
        let url = URL(string: "\(baseURL)/users/\(id)")!
        return try await performRequest(url: url, method: "GET")
    }

    func updateProfile(displayName: String?, profileImageUrl: String?, bio: String?) async throws -> User {
        struct UpdateProfileRequest: Codable {
            let displayName: String?
            let profileImageUrl: String?
            let bio: String?
        }

        let url = URL(string: "\(baseURL)/users/me")!
        let request = UpdateProfileRequest(displayName: displayName, profileImageUrl: profileImageUrl, bio: bio)
        return try await performRequest(url: url, method: "PUT", body: request)
    }

    // MARK: - Post Endpoints

    func createPost(request: CreatePostRequest) async throws -> Post {
        let url = URL(string: "\(baseURL)/posts")!
        return try await performRequest(url: url, method: "POST", body: request)
    }

    func getMutualFollowsFeed() async throws -> [Post] {
        let url = URL(string: "\(baseURL)/posts/feed")!
        return try await performRequest(url: url, method: "GET")
    }

    func getUserPosts(userId: Int64, page: Int = 0, size: Int = 20) async throws -> [Post] {
        let url = URL(string: "\(baseURL)/posts/user/\(userId)?page=\(page)&size=\(size)")!
        return try await performRequest(url: url, method: "GET")
    }

    // MARK: - Follow Endpoints

    func followUser(userId: Int64) async throws {
        let url = URL(string: "\(baseURL)/follows/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "POST")
    }

    func unfollowUser(userId: Int64) async throws {
        let url = URL(string: "\(baseURL)/follows/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Like Endpoints

    func likePost(postId: Int64) async throws {
        let url = URL(string: "\(baseURL)/posts/\(postId)/likes")!
        let _: EmptyResponse = try await performRequest(url: url, method: "POST")
    }

    func unlikePost(postId: Int64) async throws {
        let url = URL(string: "\(baseURL)/posts/\(postId)/likes")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Block Endpoints

    func blockUser(userId: Int64) async throws {
        let url = URL(string: "\(baseURL)/blocks/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "POST")
    }

    func unblockUser(userId: Int64) async throws {
        let url = URL(string: "\(baseURL)/blocks/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Report Endpoints

    func reportPost(postId: Int64, reason: String, description: String?) async throws {
        let url = URL(string: "\(baseURL)/reports")!
        let body = CreateReportRequest(postId: postId, reason: reason, description: description)
        let _: EmptyResponse = try await performRequest(url: url, method: "POST", body: body)
    }

    // MARK: - Music Token Endpoints

    func getMusicDeveloperToken() async throws -> String {
        struct TokenResponse: Codable {
            let token: String
        }
        let url = URL(string: "\(baseURL)/music/developer-token")!
        let response: TokenResponse = try await performRequest(url: url, method: "GET", requiresAuth: false)
        return response.token
    }

    func searchMusic(query: String) async throws -> [String: Any] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        let url = URL(string: "\(baseURL)/music/search?query=\(encodedQuery)")!
        let data = try await performRawRequest(url: url, method: "GET", requiresAuth: false)

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw APIError.decodingFailed(NSError(domain: "JSONSerialization", code: -1, userInfo: nil))
        }

        return json
    }

    func getSongDetails(songId: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/music/songs/\(songId)")!
        let data = try await performRawRequest(url: url, method: "GET", requiresAuth: false)

        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw APIError.decodingFailed(NSError(domain: "JSONSerialization", code: -1, userInfo: nil))
        }

        return json
    }

    // MARK: - Generic Request Handler

    private func performRawRequest(
        url: URL,
        method: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add JWT token if authenticated
        if requiresAuth, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }

    private func performRequest<T: Decodable>(
        url: URL,
        method: String,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add JWT token if authenticated
        if requiresAuth, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        // Handle empty responses
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        // Handle empty data
        if data.isEmpty {
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}

// Empty response for endpoints that don't return data
struct EmptyResponse: Codable {}
