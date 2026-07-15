import FirebaseAuth
import FirebaseStorage
import UIKit

enum MediaUploaderError: LocalizedError {
    case notAuthenticated
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You need to sign in again."
        case .invalidImage: return "That photo couldn't be processed. Try a different one."
        }
    }
}

/// Uploads voice-comment audio and chat photo/voice media to Firebase
/// Storage. Comment audio returns a storage PATH — the backend resolves the
/// download URL server-side (same convention as a post's photoStoragePath);
/// chat media returns a download URL directly, since chat messages are
/// written straight to Firestore from the client with no backend round-trip.
enum MediaUploader {
    /// commentAudio/{uid}/{uuid}.m4a
    static func uploadCommentAudio(_ fileURL: URL) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw MediaUploaderError.notAuthenticated }
        let path = "commentAudio/\(uid)/\(UUID().uuidString).m4a"
        try await uploadAudioFile(fileURL, toPath: path)
        return path
    }

    /// chatMedia/{uid}/{uuid}.jpg
    static func uploadChatPhoto(_ image: UIImage) async throws -> URL {
        guard let uid = Auth.auth().currentUser?.uid else { throw MediaUploaderError.notAuthenticated }
        guard let data = PhotoUploader.downscaledJPEG(from: image) else { throw MediaUploaderError.invalidImage }
        let path = "chatMedia/\(uid)/\(UUID().uuidString).jpg"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL()
    }

    /// chatMedia/{uid}/{uuid}.m4a
    static func uploadChatAudio(_ fileURL: URL) async throws -> URL {
        guard let uid = Auth.auth().currentUser?.uid else { throw MediaUploaderError.notAuthenticated }
        let path = "chatMedia/\(uid)/\(UUID().uuidString).m4a"
        let ref = Storage.storage().reference(withPath: path)
        try await uploadAudioFile(fileURL, toRef: ref)
        return try await ref.downloadURL()
    }

    private static func uploadAudioFile(_ fileURL: URL, toPath path: String) async throws {
        try await uploadAudioFile(fileURL, toRef: Storage.storage().reference(withPath: path))
    }

    private static func uploadAudioFile(_ fileURL: URL, toRef ref: StorageReference) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"
        _ = try await ref.putFileAsync(from: fileURL, metadata: metadata)
    }
}
