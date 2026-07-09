import Foundation

struct BlockedUser: Codable, Identifiable, Equatable {
    var uid: String
    var displayName: String?
    var blockedAt: Date

    var id: String { uid }
}

/// Local record of who you've blocked. The backend stores blocks but exposes
/// no list endpoint, so the app remembers them on-device; unblocking calls
/// DELETE /api/blocks/{uid} and forgets the entry.
@Observable
final class BlockStore {
    static let shared = BlockStore()

    private(set) var blocked: [BlockedUser] = []

    private static let defaultsKey = "drokpo.blockedUsers"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([BlockedUser].self, from: data) {
            blocked = saved
        }
    }

    func record(uid: String, displayName: String?) {
        guard !blocked.contains(where: { $0.uid == uid }) else { return }
        blocked.insert(BlockedUser(uid: uid, displayName: displayName, blockedAt: .now), at: 0)
        persist()
    }

    func unblock(_ user: BlockedUser) async throws {
        let _: EmptyResponse = try await APIClient.shared.delete("/api/blocks/\(user.uid)")
        blocked.removeAll { $0.uid == user.uid }
        persist()
    }

    /// Clear local state on sign-out; the entries belong to the old account.
    func reset() {
        blocked = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(blocked), forKey: Self.defaultsKey)
    }
}
