import SwiftUI

/// A community post card in the Discover deck — same full-bleed swipe-card
/// chrome as AdCardView/NewsCardView. Voting itself only happens in the
/// expanded detail sheet (CommunityPostContentView), so a poll's option taps
/// never fight the card's drag-to-swipe gesture.
struct CommunityPostCardView: View {
    let post: CommunityPostCard
    /// Open the post's link (same as swiping right); nil when the post has no
    /// link, or this isn't the top card.
    var onOpen: (() -> Void)? = nil
    /// Show the full detail sheet (poll voting, full body); nil when not the top card.
    var onExpand: (() -> Void)? = nil

    private var photos: [Photo] { post.displayPhotos }

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
                    if let communityName = post.communityName, !communityName.isEmpty {
                        Text(communityName.uppercased())
                            .font(.caption.bold())
                            .opacity(0.85)
                    }
                    Text(post.title ?? "—")
                        .font(.title2.bold())
                    if post.kind == "event", let date = post.eventDate {
                        Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.subheadline.bold())
                    }
                    if let body = post.body, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .lineLimit(3)
                            .opacity(0.95)
                    }
                    if post.kind == "event" {
                        HStack {
                            Text("\(post.attendeeCount ?? 0) going")
                                .font(.subheadline)
                                .opacity(0.9)
                            Spacer()
                            if onOpen != nil {
                                // Right-swipe only ever RSVPs *in*; cancelling
                                // happens in the detail sheet — say so.
                                Text(post.myRsvp == true ? "You're going ✓ — tap for details" : "Swipe right to join")
                                    .font(.caption.bold())
                            }
                        }
                        .padding(.top, 2)
                    } else if post.kind == "poll" {
                        Label("Tap to vote", systemImage: "chart.bar.fill")
                            .font(.subheadline.bold())
                            .padding(.top, 2)
                    } else if onOpen != nil {
                        Button {
                            onOpen?()
                        } label: {
                            Text(post.ctaLabel?.isEmpty == false ? post.ctaLabel! : "Learn more")
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
                Text("Community")
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
            // Whole card (photo, chevron, text) expands the detail sheet;
            // the CTA Button keeps priority over this ancestor gesture.
            .contentShape(Rectangle())
            .onTapGesture { onExpand?() }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 6, y: 3)
        }
    }
}
