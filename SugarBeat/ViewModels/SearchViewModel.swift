import Foundation
import Combine
import FirebaseAuth

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func search() {
        // Cancel previous search
        searchTask?.cancel()

        guard !searchQuery.isEmpty else {
            users = []
            return
        }

        searchTask = Task {
            isLoading = true
            errorMessage = nil

            // Debounce
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            do {
                users = try await FirestoreUserManager.shared.searchUsers(query: searchQuery)
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Search failed: \(error.localizedDescription)"
                }
            }

            isLoading = false
        }
    }
}
