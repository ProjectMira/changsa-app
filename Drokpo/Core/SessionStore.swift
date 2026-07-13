import Foundation
import FirebaseAuth

@Observable
final class SessionStore {
    enum State: Equatable {
        case loading, signedOut
        /// Signed in, no `users/{uid}` or `communities/{uid}` doc yet — the
        /// app asks whether this account is a person or a community.
        case choosingAccountType
        case needsOnboarding, activePerson
        case needsCommunityOnboarding, activeCommunity
        case failed
    }

    var state: State = .loading
    var myProfile: Profile?
    var myCommunity: CommunityProfile?
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
                    self.myCommunity = nil
                    BlockStore.shared.reset()
                    self.state = .signedOut
                } else {
                    await self.refreshAccount()
                }
            }
        }
    }

    /// The single call the app makes after sign-in (and after either
    /// onboarding flow completes) to decide which experience to route into —
    /// person, community, or neither yet.
    @MainActor
    func refreshAccount() async {
        do {
            let account: AccountResponse = try await APIClient.shared.get("/api/account")
            switch account.accountType {
            case "person":
                myProfile = account.profile
                myCommunity = nil
                state = (account.profile?.onboardingComplete ?? true) ? .activePerson : .needsOnboarding
                if state == .activePerson {
                    PushService.shared.enable()
                }
            case "community":
                myProfile = nil
                myCommunity = account.community
                state = .activeCommunity
            default:
                myProfile = nil
                myCommunity = nil
                state = .choosingAccountType
            }
        } catch {
            lastError = error.localizedDescription
            state = .failed
        }
    }

    /// Kept as the name every existing screen already calls to mean "my
    /// account state may have changed, re-fetch it" — not person-specific
    /// despite the name, now that there are two account types.
    @MainActor
    func refreshProfile() async {
        await refreshAccount()
    }

    /// Chosen on AccountTypeChoiceView, before either onboarding endpoint has
    /// run. Purely local routing — the account only becomes real once the
    /// matching onboarding flow submits.
    func chooseAccountType(_ type: AccountType) {
        state = type == .person ? .needsOnboarding : .needsCommunityOnboarding
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

enum AccountType {
    case person, community
}
