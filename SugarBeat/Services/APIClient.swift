import Foundation

enum APIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(statusCode: Int, data: Data?)
    case decodingFailed(Error)
    case unauthorized
    case serverError(message: String, statusCode: Int)

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .requestFailed(let error):
            return "リクエストに失敗しました: \(error.localizedDescription)"
        case .invalidResponse(let statusCode, _):
            return "サーバーエラー (ステータスコード: \(statusCode))"
        case .decodingFailed(let error):
            return "データの解析に失敗しました: \(error.localizedDescription)"
        case .unauthorized:
            return "認証が必要です"
        case .serverError(let message, _):
            return message
        }
    }
}

struct ErrorResponse: Codable {
    let message: String
    let status: Int
    let timestamp: String?
}

class APIClient {
    static let shared = APIClient()

    // MARK: - Environment Configuration

    enum Environment {
        case dev
        case prod

        var baseURL: String {
            switch self {
            case .dev:
                return "http://192.168.0.2:8080/api"
            case .prod:
                return "https://recoreco.net/api"
            }
        }

        var serverBaseURL: String {
            switch self {
            case .dev:
                return "http://192.168.0.2:8080"
            case .prod:
                return "https://recoreco.net"
            }
        }
    }

    // テストモード切り替え（本番リリース時にfalseに変更）
    static let isTestMode = false

    // 環境を変更する場合はここを .dev または .prod に変更
    private let environment: Environment = .prod

    private var baseURL: String { environment.baseURL }
    private var serverBaseURL: String { environment.serverBaseURL }
    private var authToken: String?
    private(set) var currentUserId: String?  // Changed from Int64 to String

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()

        // snake_case to camelCase conversion
        decoder.keyDecodingStrategy = .convertFromSnakeCase

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

    func setCurrentUserId(_ userId: String) {
        self.currentUserId = userId
    }

    func clearAuthToken() {
        self.authToken = nil
        self.currentUserId = nil
    }

    // Convert relative image paths to full URLs
    func getFullImageURL(_ imageURL: String?) -> String? {
        guard let imageURL = imageURL, !imageURL.isEmpty else { return nil }

        // If already a full URL, return as is
        if imageURL.starts(with: "http://") || imageURL.starts(with: "https://") {
            return imageURL
        }

        // If relative path, prepend server base URL with /api context path
        // サーバーのcontext-pathが/apiなので、静的リソースも/api/uploads/...になる
        if imageURL.starts(with: "/uploads/") {
            return serverBaseURL + "/api" + imageURL
        }

        return serverBaseURL + imageURL
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

    func googleAuth(request: GoogleAuthRequest) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/google")!
        return try await performRequest(url: url, method: "POST", body: request, requiresAuth: false)
    }

    func appleAuth(request: AppleAuthRequest) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/apple")!
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

    func getUser(id: String) async throws -> User {
        let url = URL(string: "\(baseURL)/users/\(id)")!
        return try await performRequest(url: url, method: "GET")
    }

    struct UpdateProfileRequest: Codable {
        let displayName: String
        let profileImageUrl: String?
        let bio: String?
    }

    func updateProfile(request: UpdateProfileRequest) async throws -> User {
        let url = URL(string: "\(baseURL)/users/me")!
        return try await performRequest(url: url, method: "PUT", body: request)
    }

    func checkUsernameAvailability(username: String) async throws -> Bool {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let url = URL(string: "\(baseURL)/users/check-username?username=\(encodedUsername)")!
        return try await performRequest(url: url, method: "GET", requiresAuth: false)
    }

    func uploadImage(imageData: Data) async throws -> String {
        let url = URL(string: "\(baseURL)/images/upload")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(statusCode: -1, data: nil)
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode, data: data)
        }

        struct UploadResponse: Codable {
            let imageUrl: String
        }

        let uploadResponse = try decoder.decode(UploadResponse.self, from: data)
        return uploadResponse.imageUrl
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

    func getDiscoveryFeed(page: Int = 0, size: Int = 20) async throws -> [Post] {
        let url = URL(string: "\(baseURL)/posts/discovery?page=\(page)&size=\(size)")!
        return try await performRequest(url: url, method: "GET", requiresAuth: false)
    }

    func getUserPosts(userId: String, page: Int = 0, size: Int = 20, sort: String = "desc") async throws -> [Post] {
        let url = URL(string: "\(baseURL)/posts/user/\(userId)?page=\(page)&size=\(size)&sort=\(sort)")!
        return try await performRequest(url: url, method: "GET")
    }

    func deletePost(postId: String) async throws {
        let url = URL(string: "\(baseURL)/posts/\(postId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Follow Endpoints

    func followUser(userId: String) async throws {
        let url = URL(string: "\(baseURL)/follows/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "POST")
    }

    func unfollowUser(userId: String) async throws {
        let url = URL(string: "\(baseURL)/follows/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    func getFollowing(userId: String) async throws -> [User] {
        let url = URL(string: "\(baseURL)/follows/\(userId)/following")!
        return try await performRequest(url: url, method: "GET")
    }

    func getFollowers(userId: String) async throws -> [User] {
        let url = URL(string: "\(baseURL)/follows/\(userId)/followers")!
        return try await performRequest(url: url, method: "GET")
    }

    // MARK: - Like Endpoints

    struct LikeResponse: Codable {
        let likeCount: Int
        let isLiked: Bool
    }

    func likePost(postId: String) async throws -> LikeResponse {
        let url = URL(string: "\(baseURL)/posts/\(postId)/likes")!
        return try await performRequest(url: url, method: "POST")
    }

    func unlikePost(postId: String) async throws -> LikeResponse {
        let url = URL(string: "\(baseURL)/posts/\(postId)/likes")!
        return try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Block Endpoints

    func blockUser(userId: String) async throws {
        let url = URL(string: "\(baseURL)/blocks/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "POST")
    }

    func unblockUser(userId: String) async throws {
        let url = URL(string: "\(baseURL)/blocks/\(userId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    func getBlockedUsers() async throws -> [User] {
        let url = URL(string: "\(baseURL)/blocks")!
        return try await performRequest(url: url, method: "GET")
    }

    // MARK: - Comment Endpoints

    func createComment(request: CreateCommentRequest) async throws -> Comment {
        let url = URL(string: "\(baseURL)/comments")!
        return try await performRequest(url: url, method: "POST", body: request)
    }

    func getComments(postId: String) async throws -> [Comment] {
        let url = URL(string: "\(baseURL)/comments/post/\(postId)")!
        return try await performRequest(url: url, method: "GET")
    }

    func deleteComment(commentId: String) async throws {
        let url = URL(string: "\(baseURL)/comments/\(commentId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Report Endpoints

    func reportComment(commentId: String, reason: String, description: String?) async throws {
        let url = URL(string: "\(baseURL)/reports/comment")!
        struct ReportCommentRequest: Codable {
            let commentId: String
            let reason: String
            let description: String?
        }
        let body = ReportCommentRequest(commentId: commentId, reason: reason, description: description)
        let _: EmptyResponse = try await performRequest(url: url, method: "POST", body: body)
    }

    func reportPost(postId: String, reason: String, description: String?) async throws {
        let url = URL(string: "\(baseURL)/reports")!
        struct ReportPostRequest: Codable {
            let postId: String
            let reason: String
            let description: String?
        }
        let body = ReportPostRequest(postId: postId, reason: reason, description: description)
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
            throw APIError.invalidResponse(statusCode: -1, data: nil)
        }

        // Handle authentication errors (401 or 403)
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            clearAuthToken()
            // Notify the app to return to login screen
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SessionExpired"), object: nil)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ API Error - Status: \(httpResponse.statusCode), URL: \(url), Response: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw APIError.invalidResponse(statusCode: httpResponse.statusCode, data: data)
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
            throw APIError.invalidResponse(statusCode: -1, data: nil)
        }

        // Handle authentication errors (401 or 403)
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            clearAuthToken()
            // Notify the app to return to login screen
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SessionExpired"), object: nil)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ API Error - Status: \(httpResponse.statusCode), URL: \(url), Response: \(String(data: data, encoding: .utf8) ?? "No data")")

            // Try to parse error response
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(message: errorResponse.message, statusCode: httpResponse.statusCode)
            }

            throw APIError.invalidResponse(statusCode: httpResponse.statusCode, data: data)
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

    // MARK: - Notification endpoints

    func getNotifications() async throws -> [Notification] {
        let url = URL(string: "\(baseURL)/notifications")!
        return try await performRequest(url: url, method: "GET")
    }

    func getUnreadNotificationCount() async throws -> Int {
        let url = URL(string: "\(baseURL)/notifications/unread-count")!
        let response: [String: Int] = try await performRequest(url: url, method: "GET")
        return response["count"] ?? 0
    }

    func deleteNotification(notificationId: String) async throws {
        let url = URL(string: "\(baseURL)/notifications/\(notificationId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    func deleteAllNotifications() async throws {
        let url = URL(string: "\(baseURL)/notifications")!
        let _: EmptyResponse = try await performRequest(url: url, method: "DELETE")
    }

    // MARK: - Unread posts endpoints

    func getUnreadPostCounts() async throws -> [String: Int] {
        let url = URL(string: "\(baseURL)/posts/unread-counts")!
        return try await performRequest(url: url, method: "GET")
    }

    func markPostsAsViewed(targetUserId: String) async throws {
        let url = URL(string: "\(baseURL)/posts/mark-viewed/\(targetUserId)")!
        let _: EmptyResponse = try await performRequest(url: url, method: "PUT")
    }
}

// Empty response for endpoints that don't return data
struct EmptyResponse: Codable {}
