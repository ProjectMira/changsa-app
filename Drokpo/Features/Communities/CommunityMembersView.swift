import SwiftUI

/// A community's member list — only reachable from CommunityDetailView once
/// you've joined (the endpoint itself also enforces this: members-only, see
/// backend docs/COMMUNITIES.md). Slim rows only: name, photo, region — never
/// the full dating-card view.
struct CommunityMembersView: View {
    let cid: String

    @State private var members: [CommunityMember] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if members.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No members yet",
                    systemImage: "person.3",
                    description: Text("Members will show up here once people join.")
                )
            } else {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        RemotePhotoView(photo: member.photo)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName ?? "Member")
                                .font(.subheadline.bold())
                            if let region = member.region, !region.isEmpty {
                                Text(region)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && members.isEmpty { ProgressView() } }
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
            let response: CommunityMembersResponse = try await APIClient.shared.get(
                "/api/communities/\(cid)/members", query: [URLQueryItem(name: "limit", value: "50")]
            )
            members = response.members ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
