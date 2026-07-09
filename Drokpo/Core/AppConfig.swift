import Foundation

enum AppConfig {
    /// Backend base URL — Firebase Hosting, which rewrites /api/** to the
    /// drokpo-api Cloud Run service.
    static let apiBaseURL = URL(string: "https://drokpo-backend.web.app")!

    /// Privacy policy hosted alongside the backend.
    static let privacyPolicyURL = URL(string: "https://drokpo-backend.web.app/privacy.html")!

    static var hasFirebaseConfig: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }
}
