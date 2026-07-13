import SafariServices
import SwiftUI

/// In-app browser (SFSafariViewController) for opening ad, news, and
/// community-post links and other external pages without leaving the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Lets `.sheet(item:)` present a plain URL (e.g. `@State private var
/// urlToOpen: URL?`) without wrapping it in another Identifiable type first.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
