import SwiftUI
import Photos
import FirebaseAuth

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileEditViewModel()
    @State private var selectedImage: UIImage?
    @State private var pendingImage: UIImage?
    @State private var showingPicker = false
    @State private var bio: String = ""

    let currentUser: User

    init(currentUser: User) {
        self.currentUser = currentUser
        _bio = State(initialValue: currentUser.bio ?? "")
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Image
                        VStack(spacing: 16) {
                            Button(action: {
                                requestPhotoLibraryPermission()
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
                                            Image("recoreco")
                                                .resizable()
                                                .scaledToFill()
                                        }
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                    } else {
                                        Image("recoreco")
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .clipShape(Circle())
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

                        // Username (read-only)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ユーザー名")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            Text(currentUser.username)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.05))
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
                                        displayName: currentUser.username,
                                        bio: bio,
                                        pendingImage: pendingImage,
                                        currentImageUrl: currentUser.profileImageUrl,
                                        currentUser: currentUser
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

    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    // 許可されたので写真選択画面を開く
                    showingPicker = true
                case .denied, .restricted:
                    // 拒否された場合は何もしない（ユーザーが設定アプリで変更可能）
                    print("写真ライブラリへのアクセスが拒否されました")
                case .notDetermined:
                    // 通常ここには来ないが、念のため
                    break
                @unknown default:
                    break
                }
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

    func saveProfile(displayName: String, bio: String, pendingImage: UIImage?, currentImageUrl: String?, currentUser: User) async {
        // Validate before submitting
        if bio.count > 20 {
            errorMessage = "プロフィール一言は20文字以内で入力してください"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var profileImageUrl: String? = currentImageUrl

            // Upload new image if selected
            if let image = pendingImage {
                print("📤 Uploading new profile image...")
                guard let userId = currentUser.id else {
                    throw NSError(domain: "ProfileEdit", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found"])
                }
                let imageUrl = try await uploadImage(image, userId: userId)
                print("✅ Image uploaded: \(imageUrl)")
                profileImageUrl = imageUrl
            } else if shouldDeleteImage {
                // Delete image
                print("🗑️ Deleting profile image...")
                profileImageUrl = nil
            }

            // Update profile directly with updateData
            guard let userId = currentUser.id else {
                throw NSError(domain: "ProfileEdit", code: -1, userInfo: [NSLocalizedDescriptionKey: "User ID not found"])
            }

            // Update profile with specific fields
            try await FirestoreUserManager.shared.updateUserProfile(
                userId: userId,
                displayName: displayName,
                bio: bio.isEmpty ? nil : bio,
                profileImageUrl: profileImageUrl
            )

            print("✅ Profile updated successfully")
        } catch {
            errorMessage = "プロフィールの更新に失敗しました: \(error.localizedDescription)"
            print("❌ Failed to update profile: \(error)")
        }

        isLoading = false
    }

    private func uploadImage(_ image: UIImage, userId: String) async throws -> String {
        // EditableImagePickerで既に正方形になっているのでリサイズのみ
        guard let resizedImage = resize(image: image, targetSize: 500) else {
            throw NSError(domain: "ImageProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
        }

        return try await FirebaseStorageManager.shared.uploadProfileImage(resizedImage, userId: userId)
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
