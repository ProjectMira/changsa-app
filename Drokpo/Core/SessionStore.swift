import Foundation
import FirebaseAuth

@Observable
final class SessionStore {
    enum State: Equatable {
        case loading, signedOut, needsOnboarding, active, failed
    }

    var state: State = .loading
    var myProfile: Profile?
    var lastError: String?

    /// Firebase Auth uid of the signed-in user; used for Firestore chat
    /// queries and unread counts.
    var uid: String? { Auth.auth().currentUser?.uid }

    /// Email of the signed-in account (nil for providers that hide it).
    var email: String? { Auth.auth().currentUser?.email }

    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        guard AppConfig.hasFirebaseConfig else {
            state = .signedOut
            return
        }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if user == nil {
                    self.myProfile = nil
                    BlockStore.shared.reset()
                    self.state = .signedOut
                } else {
                    await self.refreshProfile()
                }
            }
        }
    }

    @MainActor
    func refreshProfile() async {
        do {
            let profile: Profile = try await APIClient.shared.get("/api/profile/me")
            myProfile = profile
            state = (profile.onboardingComplete ?? true) ? .active : .needsOnboarding
            if state == .active {
                PushService.shared.enable()
            }
        } catch APIError.http(let status, _) where status == 404 {
            state = .needsOnboarding
        } catch {
            lastError = error.localizedDescription
            state = .failed
        }
    }

    func signOut() {
        Task {
            // Detach this device from push notifications while the auth
            // session is still valid, then sign out.
            await PushService.shared.unregister()
            try? Auth.auth().signOut()
        }
    }
}
