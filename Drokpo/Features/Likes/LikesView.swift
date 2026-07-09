import SwiftUI

struct LikesView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case received = "Liked you"
        case given = "You liked"

        var id: String { rawValue }
    }

    @State private var direction: Direction = .received
    @State private var received: [SwipeEntry] = []
    @State private var given: [SwipeEntry] = []
    @State private var isLoading = true
    @State private var matchedName: String?
    @State private var errorMessage: String?

    private var entries: [SwipeEntry] {
        direction == .received ? received : given
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Direction", selection: $direction) {
                    ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if isLoading {
                        ProgressView().frame(maxHeight: .infinity)
                    } else if entries.isEmpty {
                        emptyState
                    } else {
                        likeList
                    }
                }
            }
            .navigationTitle("Likes")
            .task { await load() }
            .refreshable { await load() }
            .alert("It's a match!", isPresented: .init(
                get: { matchedName != nil },
                set: { if !$0 { matchedName = nil } }
            )) {
                Button("Nice!", role: .cancel) {}
            } message: {
                Text("You and \(matchedName ?? "they") liked each other. Say hi in Chats!")
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

    private var likeList: some View {
        List(entries) { entry in
            if let card = entry.otherUser {
                NavigationLink {
                    ProfileDetailView(card: card)
                } label: {
                    HStack(spacing: 12) {
                        RemotePhotoView(photo: card.photos?.first)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(card.displayName ?? "—").font(.headline)
                                if let age = card.displayAge {
                                    Text("\(age)").foregroundStyle(.secondary)
                                }
                            }
                            if let region = card.region {
                                Text(region)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if direction == .received {
                            Button {
                                Task { await likeBack(card) }
                            } label: {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                                    .padding(8)
                                    .background(Circle().fill(.quaternary))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: direction == .received ? "heart" : "paperplane")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(direction == .received ? "No likes yet" : "You haven't liked anyone yet")
                .font(.headline)
            Text(direction == .received
                 ? "Likes you receive will show up here."
                 : "People you like in Discover will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }

    private func load() async {
        do {
            async let receivedList: TolerantList<SwipeEntry> = APIClient.shared.get(
                "/api/swipes/received", query: [URLQueryItem(name: "action", value: "like")]
            )
            async let givenList: TolerantList<SwipeEntry> = APIClient.shared.get(
                "/api/swipes", query: [URLQueryItem(name: "action", value: "like")]
            )
            received = try await receivedList.items
            given = try await givenList.items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func likeBack(_ card: FeedCard) async {
        do {
            let result: SwipeResult = try await APIClient.shared.post(
                "/api/swipes/\(card.uid)", body: SwipeIn(action: .like)
            )
            received.removeAll { $0.otherUser?.uid == card.uid }
            if result.isMatch {
                matchedName = card.displayName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
