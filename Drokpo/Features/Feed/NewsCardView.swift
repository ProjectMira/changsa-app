import SwiftUI

/// A news card in the Discover deck — same full-bleed swipe-card chrome as
/// AdCardView, driven by the news-digest skill's gist text instead of an ad
/// pitch. Swiping right (or tapping the CTA) opens the source article in the
/// in-app browser; tapping the card itself opens the full summary.
struct NewsCardView: View {
    let item: NewsCard
    /// Open the source article (same as swiping right); nil when not the top card.
    var onOpen: (() -> Void)? = nil
    /// Show the full-summary detail sheet; nil when not the top card.
    var onExpand: (() -> Void)? = nil

    private var photos: [Photo] { item.displayPhotos }

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
                    if let sourceName = item.sourceName, !sourceName.isEmpty {
                        Text(sourceName.uppercased())
                            .font(.caption.bold())
                            .opacity(0.85)
                    }
                    Text(item.title ?? "—")
                        .font(.title2.bold())
                    if let gist = item.gist, !gist.isEmpty {
                        Text(gist)
                            .font(.subheadline)
                            .lineLimit(3)
                            .opacity(0.95)
                    }
                    if onOpen != nil {
                        Button {
                            onOpen?()
                        } label: {
                            Text("Read the full story")
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
                .contentShape(Rectangle())
                .onTapGesture { onExpand?() }
            }
            .overlay(alignment: .topLeading) {
                Text("News")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if onExpand != nil {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
