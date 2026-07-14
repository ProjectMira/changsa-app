import SafariServices
import SwiftUI

/// In-app browser (SFSafariViewController) for opening ad, news, and
/// community-post links and other external pages without leaving the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // SFSafariViewController throws an NSException (crash) for anything
        // but http(s). The backend validates link fields, but a Firestore doc
        // edited outside those validators must not be able to crash the app.
        let safeURL = (url.scheme == "https" || url.scheme == "http")
            ? url
            : URL(string: "https://drokpo-backend.web.app")!
        return SFSafariViewController(url: safeURL)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Lets `.sheet(item:)` present a plain URL (e.g. `@State private var
/// urlToOpen: URL?`) without wrapping it in another Identifiable type first.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
