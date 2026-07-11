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
    @State private var matched: (name: String, matchId: String?)?
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
            .onAppear { Task { await load() } }
            .refreshable { await load() }
            .alert("It's a match!", isPresented: .init(
                get: { matched != nil },
                set: { if !$0 { matched = nil } }
            )) {
                Button("Say hi") {
                    if let matchId = matched?.matchId {
                        DeepLinkRouter.shared.handle(type: "message", matchId: matchId)
                    }
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text("You and \(matched?.name ?? "they") liked each other.")
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
                    destination(for: card)
                } label: {
                    LikeRow(card: card, showLikeBack: direction == .received) {
                        Task { await likeBackFromRow(card) }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func destination(for card: FeedCard) -> some View {
        if direction == .received {
            ProfileDetailView(
                card: card,
                context: .likedYou(onLikeBack: { await likeBack(card) })
            )
        } else {
            ProfileDetailView(card: card)
        }
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

    /// Only shows the full-screen spinner on the very first load; later calls
    /// (tab reselected, pull-to-refresh, returning from a like push) refresh
    /// silently so the existing list doesn't flash.
    ///
    /// Matched people are dropped from both lists — they already show up in
    /// Chats (New matches / conversations), so keeping them here duplicated
    /// the same person under both "Liked you" and "You liked".
    private func load() async {
        if received.isEmpty && given.isEmpty { isLoading = true }
        do {
            async let receivedList: TolerantList<SwipeEntry> = APIClient.shared.get(
                "/api/swipes/received", query: [URLQueryItem(name: "action", value: "like")]
            )
            async let givenList: TolerantList<SwipeEntry> = APIClient.shared.get(
                "/api/swipes", query: [URLQueryItem(name: "action", value: "like")]
            )
            received = try await receivedList.items.filter { !$0.isMatched }
            given = try await givenList.items.filter { !$0.isMatched }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Shared by both the row's quick-like heart and the pushed
    /// ProfileDetailView's "Like back" button. Only removes the row from
    /// `received` — it does NOT set `matched`, because ProfileDetailView
    /// shows its own match alert and setting `matched` here too would
    /// present two alerts for the same tap.
    @discardableResult
    private func likeBack(_ card: FeedCard) async -> SwipeResult? {
        do {
            let result: SwipeResult = try await APIClient.shared.post(
                "/api/swipes/\(card.uid)", body: SwipeIn(action: .like)
            )
            received.removeAll { $0.otherUser?.uid == card.uid }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func likeBackFromRow(_ card: FeedCard) async {
        guard let result = await likeBack(card), result.isMatch else { return }
        matched = (name: card.displayName ?? "they", matchId: result.matchId ?? result.match?.matchId)
    }
}

/// A single Likes-list row. Pulled out of `LikesView.likeList` into its own
/// view — nesting this much conditional content directly inside a `List`
/// row closure made the type checker choke on `List(entries) { ... }`
/// itself (a bogus "cannot convert to Binding<Data>" error unrelated to the
/// real content); a dedicated view type keeps each closure's body small
/// enough to type-check.
private struct LikeRow: View {
    let card: FeedCard
    let showLikeBack: Bool
    let onLikeBack: () -> Void

    var body: some View {
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
            if showLikeBack {
                Button(action: onLikeBack) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.brandRed)
                        .padding(8)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
