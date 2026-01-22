import Foundation
import FirebaseStorage
import UIKit

enum StorageError: Error {
    case invalidImageData
    case uploadFailed(Error)
    case downloadFailed(Error)
    case deleteFailed(Error)
    case invalidURL

    var localizedDescription: String {
        switch self {
        case .invalidImageData:
            return "無効な画像データです"
        case .uploadFailed(let error):
            return "アップロードに失敗しました: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "ダウンロードに失敗しました: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "削除に失敗しました: \(error.localizedDescription)"
        case .invalidURL:
            return "無効なURLです"
        }
    }
}

class FirebaseStorageManager {
    static let shared = FirebaseStorageManager()
    private let storage = Storage.storage()

    private init() {}

    // MARK: - Profile Images

    func uploadProfileImage(_ image: UIImage, userId: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw StorageError.invalidImageData
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "users/\(userId)/profile/\(timestamp).jpg"
        let storageRef = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            return downloadURL.absoluteString
        } catch {
            throw StorageError.uploadFailed(error)
        }
    }

    func deleteProfileImage(url: String) async throws {
        guard let storageRef = storage.reference(forURL: url) as? StorageReference else {
            throw StorageError.invalidURL
        }

        do {
            try await storageRef.delete()
        } catch {
            throw StorageError.deleteFailed(error)
        }
    }

    // MARK: - Post Images

    func uploadPostImage(_ image: UIImage, userId: String, postId: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw StorageError.invalidImageData
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "users/\(userId)/posts/\(postId)/\(timestamp).jpg"
        let storageRef = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            return downloadURL.absoluteString
        } catch {
            throw StorageError.uploadFailed(error)
        }
    }

    func deletePostImage(url: String) async throws {
        guard let storageRef = storage.reference(forURL: url) as? StorageReference else {
            throw StorageError.invalidURL
        }

        do {
            try await storageRef.delete()
        } catch {
            throw StorageError.deleteFailed(error)
        }
    }

    // MARK: - Generic Image Upload

    func uploadImage(_ image: UIImage, path: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw StorageError.invalidImageData
        }

        let storageRef = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            return downloadURL.absoluteString
        } catch {
            throw StorageError.uploadFailed(error)
        }
    }

    // MARK: - Temp Uploads

    func uploadTempImage(_ image: UIImage, userId: String) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw StorageError.invalidImageData
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "uploads/temp/\(userId)/\(timestamp).jpg"
        let storageRef = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            let _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            return downloadURL.absoluteString
        } catch {
            throw StorageError.uploadFailed(error)
        }
    }

    func deleteTempImage(url: String) async throws {
        guard let storageRef = storage.reference(forURL: url) as? StorageReference else {
            throw StorageError.invalidURL
        }

        do {
            try await storageRef.delete()
        } catch {
            throw StorageError.deleteFailed(error)
        }
    }

    // MARK: - Download Image

    func downloadImage(url: String) async throws -> UIImage {
        guard let storageRef = storage.reference(forURL: url) as? StorageReference else {
            throw StorageError.invalidURL
        }

        do {
            let data = try await storageRef.data(maxSize: 10 * 1024 * 1024) // 10MB max
            guard let image = UIImage(data: data) else {
                throw StorageError.invalidImageData
            }
            return image
        } catch {
            throw StorageError.downloadFailed(error)
        }
    }
}
