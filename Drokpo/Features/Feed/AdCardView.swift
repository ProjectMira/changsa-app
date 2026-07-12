import SwiftUI

/// A sponsored card in the Discover deck. Mirrors CardView's layout so it
/// feels native to the deck, but is clearly labelled and swaps the profile
/// info for the ad's pitch plus a call-to-action.
struct AdCardView: View {
    let ad: AdCard
    /// Open the ad link (same as swiping right); nil when not the top card.
    var onOpen: (() -> Void)? = nil

    private var photos: [Photo] { ad.displayPhotos }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if let photo = photos.first {
                    RemotePhotoView(photo: photo)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.85), .brandRed.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 8) {
                    Text(ad.title ?? "—")
                        .font(.title.bold())
                    if let body = ad.body, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .lineLimit(3)
                            .opacity(0.95)
                    }
                    if onOpen != nil {
                        Button {
                            onOpen?()
                        } label: {
                            Text(ad.ctaLabel?.isEmpty == false ? ad.ctaLabel! : "Learn more")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
                .foregroundStyle(.white)
                .padding()
            }
            .overlay(alignment: .topLeading) {
                Text("Sponsored")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
