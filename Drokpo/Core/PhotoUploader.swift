import FirebaseAuth
import FirebaseStorage
import UIKit

enum PhotoUploaderError: LocalizedError {
    case notAuthenticated
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You need to sign in again."
        case .invalidImage: return "That photo couldn't be processed. Try a different one."
        }
    }
}

enum PhotoUploader {
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.8

    /// Uploads a profile photo to Firebase Storage and returns its storage path
    /// for the backend confirm endpoints.
    static func upload(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoUploaderError.notAuthenticated }
        return try await upload(image, toPath: "users/\(uid)/photos/\(UUID().uuidString).jpg")
    }

    /// Same as `upload(_:)` but under a community's own Storage prefix
    /// (`communities/{uid}/photos/…`, enforced by storage.rules).
    static func uploadCommunityPhoto(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw PhotoUploaderError.notAuthenticated }
        return try await upload(image, toPath: "communities/\(uid)/photos/\(UUID().uuidString).jpg")
    }

    @discardableResult
    private static func upload(_ image: UIImage, toPath path: String) async throws -> String {
        guard let data = downscaledJPEG(from: image) else { throw PhotoUploaderError.invalidImage }
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return path
    }

    static func downloadURL(for storagePath: String) async throws -> URL {
        try await Storage.storage().reference(withPath: storagePath).downloadURL()
    }

    /// Shared with MediaUploader (chat photo messages) — same downscale
    /// rationale as profile/community photos, just not a private detail
    /// anymore now that another type needs it.
    static func downscaledJPEG(from image: UIImage) -> Data? {
        // Work in pixels, not points: image.size is in points and the renderer
        // multiplies by its scale, so a screen-scale renderer would upscale a
        // 1600pt canvas to 4800px and blow past the 10MB storage rule limit.
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let largestSide = max(pixelSize.width, pixelSize.height)
        guard largestSide > maxDimension else { return image.jpegData(compressionQuality: jpegQuality) }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }
}
