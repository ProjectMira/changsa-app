import FirebaseFirestore
import Foundation

/// Real-time source for the chat list. Match membership is decided by the
/// backend (the swipe transaction), but once matches exist the client listens
/// to them directly — the Firestore rules allow participants to read their own
/// match docs — so previews and unread counts update live. Profiles of the
/// other participants aren't client-readable, so those come from the REST
/// GET /api/matches, which joins them server-side.
@Observable
final class ChatStore {
    struct Entry: Identifiable, Equatable {
        var matchId: String
        var otherUid: String
        var otherUser: FeedCard?
        var lastMessageText: String?
        var lastMessageSenderId: String?
        var unread: Int
        var sortDate: Date

        var id: String { matchId }
        var hasMessages: Bool { lastMessageText != nil }
    }

    private(set) var entries: [Entry] = []
    private(set) var isLoading = true
    var errorMessage: String?

    private var profiles: [String: FeedCard] = [:]
    private var listener: ListenerRegistration?
    private var uid: String?

    var totalUnread: Int { entries.reduce(0) { $0 + $1.unread } }

    /// Matches with no conversation yet, newest first.
    var newMatches: [Entry] { entries.filter { !$0.hasMessages } }
    /// Ongoing conversations, most recent message first.
    var conversations: [Entry] { entries.filter(\.hasMessages) }

    func start(uid: String) {
        guard self.uid != uid else { return }
        self.uid = uid
        listener?.remove()
        listener = Firestore.firestore()
            .collection("matches")
            .whereField("users", arrayContains: uid)
            .whereField("status", isEqualTo: "active")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                self.apply(documents: snapshot?.documents ?? [])
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        uid = nil
        entries = []
        profiles = [:]
        isLoading = true
    }

    private func apply(documents: [QueryDocumentSnapshot]) {
        guard let uid else { return }
        var missingProfiles = false

        entries = documents.compactMap { doc in
            let data = doc.data()
            guard let users = data["users"] as? [String],
                  let otherUid = users.first(where: { $0 != uid }) else { return nil }
            let lastMessage = data["lastMessage"] as? [String: Any]
            let sortDate = (lastMessage?["createdAt"] as? Timestamp)?.dateValue()
                ?? (data["createdAt"] as? Timestamp)?.dateValue()
                ?? .distantPast
            if profiles[otherUid] == nil { missingProfiles = true }
            return Entry(
                matchId: doc.documentID,
                otherUid: otherUid,
                otherUser: profiles[otherUid],
                lastMessageText: lastMessage?["text"] as? String,
                lastMessageSenderId: lastMessage?["senderId"] as? String,
                unread: (data["unreadCount"] as? [String: Int])?[uid] ?? 0,
                sortDate: sortDate
            )
        }
        .sorted { $0.sortDate > $1.sortDate }

        if missingProfiles {
            Task { await loadProfiles() }
        } else {
            isLoading = false
        }
    }

    @MainActor
    private func loadProfiles() async {
        do {
            let list: TolerantList<Match> = try await APIClient.shared.get("/api/matches")
            for match in list.items {
                if let other = match.otherUser {
                    profiles[other.uid] = other
                }
            }
            entries = entries.map { entry in
                var updated = entry
                updated.otherUser = profiles[entry.otherUid]
                return updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Optimistically clear the local unread badge; the server-side counter is
    /// reset by POST /matches/{id}/read from the thread view.
    func clearUnread(matchId: String) {
        if let index = entries.firstIndex(where: { $0.matchId == matchId }) {
            entries[index].unread = 0
        }
    }
}
