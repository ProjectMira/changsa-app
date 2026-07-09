import SwiftUI

/// Full-screen look at another member's profile, pushed from the chats and
/// likes lists.
struct ProfileDetailView: View {
    let card: FeedCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photos = card.photos, !photos.isEmpty {
                    TabView {
                        ForEach(photos) { photo in
                            RemotePhotoView(photo: photo)
                        }
                    }
                    .tabViewStyle(.page)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.displayName ?? "—")
                            .font(.title.bold())
                        if let age = card.displayAge {
                            Text("\(age)").font(.title2)
                        }
                    }
                    if let region = card.region {
                        Label(region, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                    if let languages = card.languages, !languages.isEmpty {
                        Label(languages.joined(separator: ", "), systemImage: "globe")
                            .foregroundStyle(.secondary)
                    }
                    if let instagram = card.socials?.instagram, !instagram.isEmpty {
                        Label("@\(instagram)", systemImage: "camera")
                            .foregroundStyle(.secondary)
                    }
                    if let interests = card.interests, !interests.isEmpty {
                        Label(interests.joined(separator: ", "), systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    }
                    if let bio = card.bio, !bio.isEmpty {
                        Text(bio).padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(card.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
