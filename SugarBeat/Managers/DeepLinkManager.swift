//
//  DeepLinkManager.swift
//  SugarBeat
//
//  Universal Links handler for profile deep links
//

import Foundation
import SwiftUI

@MainActor
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var pendingProfileUsername: String?
    @Published var showingDeepLinkError = false
    @Published var deepLinkErrorMessage: String?

    private init() {}

    /// Handle incoming Universal Link
    /// Expected format: https://appuppu.github.io/docs/profile/{username}
    func handleUniversalLink(_ url: URL) -> Bool {
        print("🔗 [DeepLinkManager] Handling URL: \(url.absoluteString)")

        // Check if this is a profile link
        guard url.host == "appuppu.github.io" || url.host == "www.appuppu.github.io" else {
            print("❌ [DeepLinkManager] Invalid host: \(url.host ?? "nil")")
            return false
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Expected: ["docs", "profile", "username"]
        guard pathComponents.count == 3,
              pathComponents[0] == "docs",
              pathComponents[1] == "profile" else {
            print("❌ [DeepLinkManager] Invalid path: \(url.path)")
            showError("無効なリンク形式です")
            return false
        }

        let username = pathComponents[2]

        // Validate username format (same as signup validation)
        guard isValidUsername(username) else {
            print("❌ [DeepLinkManager] Invalid username format: \(username)")
            showError("無効なユーザー名です")
            return false
        }

        print("✅ [DeepLinkManager] Valid profile link for username: \(username)")
        pendingProfileUsername = username

        return true
    }

    /// Validate username format
    private func isValidUsername(_ username: String) -> Bool {
        // Must be 1-10 characters
        guard username.count >= 1 && username.count <= 10 else {
            return false
        }

        // Must contain only alphanumeric, dot, underscore
        let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._"))
        return username.unicodeScalars.allSatisfy { allowedCharacterSet.contains($0) }
    }

    /// Clear pending deep link
    func clearPendingLink() {
        pendingProfileUsername = nil
    }

    /// Show error message
    private func showError(_ message: String) {
        deepLinkErrorMessage = message
        showingDeepLinkError = true
    }

    /// Generate profile URL for a username
    static func generateProfileURL(username: String) -> URL? {
        // Validate username before generating URL
        guard DeepLinkManager.shared.isValidUsername(username) else {
            print("❌ [DeepLinkManager] Cannot generate URL for invalid username: \(username)")
            return nil
        }

        return URL(string: "https://appuppu.github.io/docs/profile/\(username)")
    }
}
