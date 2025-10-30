import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileEditViewModel()
    @State private var selectedImage: UIImage?
    @State private var pendingImage: UIImage?
    @State private var showingPicker = false
    @State private var displayName: String = ""
    @State private var bio: String = ""

    let currentUser: User

    init(currentUser: User) {
        self.currentUser = currentUser
        _displayName = State(initialValue: currentUser.displayName)
        _bio = State(initialValue: currentUser.bio ?? "")
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Image
                        VStack(spacing: 16) {
                            Button(action: {
                                showingPicker = true
                            }) {
                                ZStack {
                                    // Profile image
                                    if let image = pendingImage {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .clipShape(Circle())
                                    } else if !viewModel.shouldDeleteImage, let imageUrl = currentUser.profileImageUrl {
                                        AsyncImage(url: URL(string: imageUrl)) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Circle()
                                                .fill(Color.white.opacity(0.2))
                                                .overlay(
                                                    Image(systemName: "person.fill")
                                                        .font(.system(size: 40))
                                                        .foregroundColor(.white.opacity(0.5))
                                                )
                                        }
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 120, height: 120)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(.white.opacity(0.5))
                                            )
                                    }

                                    // Edit overlay
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 120, height: 120)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.white)
                                        )
                                }
                            }

                            // Delete image button
                            if (pendingImage != nil || (currentUser.profileImageUrl != nil && !viewModel.shouldDeleteImage)) {
                                Button(action: {
                                    pendingImage = nil
                                    viewModel.shouldDeleteImage = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 14))
                                        Text("画像を削除")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.top, 32)

                        // Display Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("表示名")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            TextField("", text: $displayName)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 20)

                        // Bio
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自己紹介")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            TextEditor(text: $bio)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .frame(height: 100)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 20)

                        // Save button
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .padding(.top, 20)
                        } else {
                            Button(action: {
                                Task {
                                    await viewModel.saveProfile(
                                        displayName: displayName,
                                        bio: bio,
                                        pendingImage: pendingImage,
                                        currentImageUrl: currentUser.profileImageUrl
                                    )
                                    if viewModel.errorMessage == nil {
                                        dismiss()
                                    }
                                }
                            }) {
                                Text("保存")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingPicker) {
                EditableImagePicker(image: $selectedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: selectedImage) { img in
                guard let img else { return }
                pendingImage = img
                viewModel.shouldDeleteImage = false
                selectedImage = nil
            }
        }
    }
}

@MainActor
class ProfileEditViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var shouldDeleteImage = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func saveProfile(displayName: String, bio: String, pendingImage: UIImage?, currentImageUrl: String?) async {
        isLoading = true
        errorMessage = nil

        do {
            var profileImageUrl: String? = currentImageUrl

            // Upload new image if selected
            if let image = pendingImage {
                print("📤 Uploading new profile image...")
                let imageUrl = try await uploadImage(image)
                print("✅ Image uploaded: \(imageUrl)")
                profileImageUrl = imageUrl
            } else if shouldDeleteImage {
                // Delete image
                print("🗑️ Deleting profile image...")
                profileImageUrl = nil
            }

            // Update profile
            let request = APIClient.UpdateProfileRequest(
                displayName: displayName,
                profileImageUrl: profileImageUrl,
                bio: bio.isEmpty ? nil : bio
            )

            let _ = try await APIClient.shared.updateProfile(request: request)

            print("✅ Profile updated successfully")
        } catch {
            errorMessage = "プロフィールの更新に失敗しました: \(error.localizedDescription)"
            print("❌ Failed to update profile: \(error)")
        }

        isLoading = false
    }

    private func uploadImage(_ image: UIImage) async throws -> String {
        // EditableImagePickerで既に正方形になっているのでリサイズのみ
        guard let resizedImage = resize(image: image, targetSize: 500),
              let imageData = compressImage(resizedImage) else {
            throw NSError(domain: "ImageProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }

        print("📦 Image data size: \(imageData.count) bytes")
        return try await APIClient.shared.uploadImage(imageData: imageData)
    }

    private func resize(image: UIImage, targetSize: CGFloat) -> UIImage? {
        let size = CGSize(width: targetSize, height: targetSize)

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func compressImage(_ image: UIImage) -> Data? {
        // Try JPEG first (smaller file size)
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            return jpegData
        }

        // Fallback to PNG
        return image.pngData()
    }
}
