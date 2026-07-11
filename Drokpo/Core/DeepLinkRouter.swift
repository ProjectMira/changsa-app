import Foundation

/// Carries a pending push-notification tap from PushService to the UI. Set on
/// tap (including cold-start), consumed by MainTabView/ChatsView which then
/// clear it. `type` distinguishes a "match" (land on the Chats list) from a
/// "message" (open the thread).
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingMatchId: String?
    var pendingType: String?

    func handle(type: String?, matchId: String?) {
        pendingType = type
        pendingMatchId = matchId
    }

    func clear() {
        pendingType = nil
        pendingMatchId = nil
    }
}
