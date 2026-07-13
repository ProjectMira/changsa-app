import SwiftUI

/// A single community's public page: header (logo, name, member count,
/// join/leave, website/socials) plus its post feed below.
struct CommunityDetailView: View {
    let cid: String
    /// Directory/rail card data, shown immediately while the fuller detail
    /// fetch is in flight — avoids a blank header on push.
    let preview: CommunityProfile?

    @State private var community: CommunityProfile?
    @State private var posts: [CommunityPostCard] = []
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var urlToOpen: URL?

    init(cid: String, preview: CommunityProfile? = nil) {
        self.cid = cid
        self.preview = preview
        _community = State(initialValue: preview)
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("Posts") {
                if posts.isEmpty && !isLoading {
                    Text("No posts yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(posts) { post in
                        postRow(post)
                    }
                }
            }
        }
        .navigationTitle(community?.name ?? "Community")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && community == nil { ProgressView() } }
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

    /// Factored out of the ForEach closure — a body with several inline
    /// ternary closures in one View initializer overwhelms the type checker.
    private func postRow(_ post: CommunityPostCard) -> some View {
        CommunityPostContentView(
            post: post,
            onVote: post.kind == "poll" ? { optionId in Task { await vote(post, optionId: optionId) } } : nil,
            onRsvp: post.kind == "event" ? { going in Task { await rsvp(post, going: going) } } : nil,
            onOpenLink: post.url != nil ? { urlToOpen = post.url } : nil
        )
        .padding(.vertical, 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemotePhotoView(photo: community?.photos?.first)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .clipped()

            HStack(spacing: 6) {
                Text(community?.name ?? "Community")
                    .font(.title3.bold())
                if community?.isVerified == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.tint)
                }
            }
            memberCountRow

            if let description = community?.description, !description.isEmpty {
                Text(description).font(.subheadline)
            }

            HStack(spacing: 12) {
                joinButton
                if let website = community?.website, let url = URL(string: website) {
                    Button {
                        urlToOpen = url
                    } label: {
                        Label("Website", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    /// A count-only label for non-members (member lists are members-only —
    /// see docs/COMMUNITIES.md), or a link into the member list once joined.
    @ViewBuilder
    private var memberCountRow: some View {
        let count = community?.memberCount ?? 0
        let label = Text("\(count) member\(count == 1 ? "" : "s")")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        if community?.joined == true {
            NavigationLink { CommunityMembersView(cid: cid) } label: { label }
        } else {
            label
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        let label = Group {
            if isJoining {
                ProgressView()
            } else {
                Text(community?.joined == true ? "Joined" : "Join")
            }
        }
        if community?.joined == true {
            Button { Task { await toggleJoin() } } label: { label }
                .buttonStyle(.bordered)
                .disabled(isJoining)
        } else {
            Button { Task { await toggleJoin() } } label: { label }
                .buttonStyle(.borderedProminent)
                .disabled(isJoining)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let communityResponse: CommunityProfile = APIClient.shared.get("/api/communities/\(cid)")
        async let postsResponse: CommunityPostsResponse = APIClient.shared.get(
            "/api/communities/\(cid)/posts", query: [URLQueryItem(name: "limit", value: "30")]
        )
        do {
            let (communityResult, postsResult) = try await (communityResponse, postsResponse)
            community = communityResult
            posts = postsResult.posts ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleJoin() async {
        isJoining = true
        defer { isJoining = false }
        let wasJoined = community?.joined == true
        do {
            if wasJoined {
                let _: EmptyResponse = try await APIClient.shared.delete("/api/communities/\(cid)/join")
                community?.joined = false
                community?.memberCount = max(0, (community?.memberCount ?? 1) - 1)
            } else {
                let _: EmptyResponse = try await APIClient.shared.post("/api/communities/\(cid)/join")
                community?.joined = true
                community?.memberCount = (community?.memberCount ?? 0) + 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func vote(_ post: CommunityPostCard, optionId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            let result: VoteResult = try await APIClient.shared.post(
                "/api/posts/\(post.postId)/vote", body: VoteIn(optionId: optionId)
            )
            posts[index].poll = result.poll
            posts[index].myVote = result.myVote
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rsvp(_ post: CommunityPostCard, going: Bool) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            let result: RsvpResult = going
                ? try await APIClient.shared.post("/api/posts/\(post.postId)/rsvp")
                : try await APIClient.shared.delete("/api/posts/\(post.postId)/rsvp")
            posts[index].attendeeCount = result.attendeeCount
            posts[index].myRsvp = result.going
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
