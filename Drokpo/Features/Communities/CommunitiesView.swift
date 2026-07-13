import SwiftUI

/// The Communities tab for person accounts: a "discover" rail of verified
/// communities up top, and the communities you've already joined below.
struct CommunitiesView: View {
    @State private var discover: [CommunityProfile] = []
    @State private var mine: [CommunityProfile] = []
    @State private var joinedFeed: [CommunityPostCard] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var urlToOpen: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if discover.isEmpty && !isLoading {
                        Text("No communities to discover yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(discover) { community in
                                    NavigationLink {
                                        CommunityDetailView(cid: community.id, preview: community)
                                    } label: {
                                        DiscoverCommunityCard(community: community)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text("Communities to discover")
                        Spacer()
                        NavigationLink("See all") { CommunityDirectoryView() }
                            .font(.subheadline)
                    }
                }

                Section("My communities") {
                    if mine.isEmpty && !isLoading {
                        Text("Join a community to see its posts here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mine) { community in
                            NavigationLink {
                                CommunityDetailView(cid: community.id, preview: community)
                            } label: {
                                CommunityRow(community: community)
                            }
                        }
                    }
                }

                Section("From your communities") {
                    if joinedFeed.isEmpty && !isLoading {
                        Text("Posts from communities you join will show up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(joinedFeed) { post in
                            feedRow(post)
                        }
                    }
                }
            }
            .navigationTitle("Communities")
            .overlay { if isLoading && discover.isEmpty && mine.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $urlToOpen) { url in
                SafariView(url: url)
            }
            .alert("Something went wrong", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Factored out of the ForEach closure — several inline ternary closures
    /// in one View initializer overwhelms the Swift type checker.
    private func feedRow(_ post: CommunityPostCard) -> some View {
        CommunityPostContentView(
            post: post,
            onVote: post.kind == "poll" ? { optionId in Task { await vote(post, optionId: optionId) } } : nil,
            onRsvp: post.kind == "event" ? { going in Task { await rsvp(post, going: going) } } : nil,
            onOpenLink: post.url != nil ? { urlToOpen = post.url } : nil
        )
        .padding(.vertical, 6)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let discoverResponse: CommunityListResponse = APIClient.shared.get(
            "/api/communities", query: [URLQueryItem(name: "limit", value: "20")]
        )
        async let mineResponse: CommunityListResponse = APIClient.shared.get("/api/communities/mine")
        async let feedResponse: CommunityPostsResponse = APIClient.shared.get("/api/communities/feed")
        do {
            let (discoverResult, mineResult, feedResult) = try await (discoverResponse, mineResponse, feedResponse)
            discover = discoverResult.communities ?? []
            mine = mineResult.communities ?? []
            joinedFeed = feedResult.posts ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func vote(_ post: CommunityPostCard, optionId: String) async {
        guard let index = joinedFeed.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            let result: VoteResult = try await APIClient.shared.post(
                "/api/posts/\(post.postId)/vote", body: VoteIn(optionId: optionId)
            )
            joinedFeed[index].poll = result.poll
            joinedFeed[index].myVote = result.myVote
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rsvp(_ post: CommunityPostCard, going: Bool) async {
        guard let index = joinedFeed.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            let result: RsvpResult = going
                ? try await APIClient.shared.post("/api/posts/\(post.postId)/rsvp")
                : try await APIClient.shared.delete("/api/posts/\(post.postId)/rsvp")
            joinedFeed[index].attendeeCount = result.attendeeCount
            joinedFeed[index].myRsvp = result.going
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Full "see all" list of verified communities, with join/leave inline.
struct CommunityDirectoryView: View {
    @State private var communities: [CommunityProfile] = []
    @State private var isLoading = true
    @State private var workingCid: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if communities.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No communities yet",
                    systemImage: "person.3",
                    description: Text("Verified communities will show up here.")
                )
            } else {
                ForEach(communities) { community in
                    NavigationLink {
                        CommunityDetailView(cid: community.id, preview: community)
                    } label: {
                        CommunityRow(community: community)
                    }
                }
            }
        }
        .navigationTitle("Discover communities")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && communities.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: CommunityListResponse = try await APIClient.shared.get(
                "/api/communities", query: [URLQueryItem(name: "limit", value: "50")]
            )
            communities = response.communities ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Shared cells

struct CommunityRow: View {
    let community: CommunityProfile

    var body: some View {
        HStack(spacing: 12) {
            RemotePhotoView(photo: community.photos?.first)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(community.name ?? "Community")
                        .font(.headline)
                    if community.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                            .font(.caption)
                    }
                }
                Text("\(community.memberCount ?? 0) member\((community.memberCount ?? 0) == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DiscoverCommunityCard: View {
    let community: CommunityProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemotePhotoView(photo: community.photos?.first)
                .frame(width: 120, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(community.name ?? "Community")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(community.memberCount ?? 0) member\((community.memberCount ?? 0) == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }
}
