import Foundation

/// One card in the Discover deck: a real member, or one of the three content
/// queues (ads, news, community posts) mixed in between them.
enum DeckItem: Equatable, Identifiable {
    case profile(FeedCard)
    case ad(AdCard)
    case news(NewsCard)
    case post(CommunityPostCard)

    var id: String {
        switch self {
        case .profile(let card): "profile-\(card.uid)"
        case .ad(let ad): "ad-\(ad.adId)"
        case .news(let news): "news-\(news.newsId)"
        case .post(let post): "post-\(post.postId)"
        }
    }

    var profileCard: FeedCard? {
        if case .profile(let card) = self { return card }
        return nil
    }
}

@Observable
final class FeedModel {
    /// How many real profiles appear between content cards.
    static let profilesPerAd = 3

    var deck: [DeckItem] = []
    var isLoading = false
    var matchedCard: FeedCard?
    var errorMessage: String?
    /// Link currently open in the in-app browser sheet — set by swiping right
    /// on an ad, news, or link-post card.
    var urlToOpen: URL?
    /// The last profile swiped this session, undoable until the next swipe.
    /// Cleared on match (undo is refused server-side once matched).
    private(set) var lastSwipedProfile: FeedCard?

    var canUndo: Bool { lastSwipedProfile != nil }

    private var isFetching = false
    /// Everyone swiped this session. The backend also filters swiped users,
    /// but a feed fetch that races an in-flight swipe POST can still return
    /// someone we just swiped — never re-add them.
    private var swipedUids: Set<String> = []

    /// Active content from the last feed response, each inserted round-robin
    /// and cycling ad -> news -> post as the deck refills.
    private var ads: [AdCard] = []
    private var news: [NewsCard] = []
    private var communityPosts: [CommunityPostCard] = []
    private var adCursor = 0
    private var newsCursor = 0
    private var postCursor = 0
    /// Which content queue serves next.
    private var contentTypeCursor = 0
    /// Profiles appended since a content card was last inserted.
    private var profilesSinceContent = 0
    /// Content cards (any type) whose impression we already reported this session.
    private var impressedContentIds: Set<String> = []

    @MainActor
    func loadInitial() async {
        guard deck.isEmpty else { return }
        isLoading = true
        await fetchMore()
        isLoading = false
    }

    @MainActor
    func fetchMore() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let response: FeedResponse = try await APIClient.shared.get(
                "/api/feed",
                query: [URLQueryItem(name: "limit", value: "20")]
            )
            ads = response.ads ?? []
            news = response.news ?? []
            communityPosts = response.communityPosts ?? []
            let known = Set(deck.compactMap { $0.profileCard?.uid })
            let fresh = (response.candidates ?? []).filter {
                !known.contains($0.uid) && !swipedUids.contains($0.uid)
            }
            appendInterleaving(fresh)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends profiles to the deck, inserting one content card after every
    /// `profilesPerAd` real profiles (when one of the three queues has
    /// something new to show).
    @MainActor
    private func appendInterleaving(_ profiles: [FeedCard]) {
        for card in profiles {
            deck.append(.profile(card))
            profilesSinceContent += 1
            if profilesSinceContent >= Self.profilesPerAd, let item = nextContentItem() {
                deck.append(item)
                profilesSinceContent = 0
            }
        }
        reportTopImpressionIfNeeded()
    }

    /// Round-robins `queue`, returning the first item not already in `deckIds`
    /// — skips a full lap if every item is already showing.
    private func nextRoundRobin<T>(_ queue: [T], cursor: inout Int, idOf: (T) -> String, deckIds: Set<String>) -> T? {
        guard !queue.isEmpty else { return nil }
        for _ in 0..<queue.count {
            let item = queue[cursor % queue.count]
            cursor += 1
            if !deckIds.contains(idOf(item)) { return item }
        }
        return nil
    }

    /// Cycles ad -> news -> post, skipping any queue that's empty or whose
    /// items are all already in the deck; nil once all three come up empty.
    private func nextContentItem() -> DeckItem? {
        let adIds = Set(deck.compactMap { item -> String? in
            if case .ad(let ad) = item { return ad.adId }
            return nil
        })
        let newsIds = Set(deck.compactMap { item -> String? in
            if case .news(let news) = item { return news.newsId }
            return nil
        })
        let postIds = Set(deck.compactMap { item -> String? in
            if case .post(let post) = item { return post.postId }
            return nil
        })
        for _ in 0..<3 {
            let item: DeckItem?
            switch contentTypeCursor % 3 {
            case 0:
                item = nextRoundRobin(ads, cursor: &adCursor, idOf: { $0.adId }, deckIds: adIds).map(DeckItem.ad)
            case 1:
                item = nextRoundRobin(news, cursor: &newsCursor, idOf: { $0.newsId }, deckIds: newsIds).map(DeckItem.news)
            default:
                item = nextRoundRobin(communityPosts, cursor: &postCursor, idOf: { $0.postId }, deckIds: postIds).map(DeckItem.post)
            }
            contentTypeCursor += 1
            if let item { return item }
        }
        return nil
    }

    /// Removes the card immediately for a snappy deck, then records the swipe.
    @MainActor
    func swipe(_ card: FeedCard, action: SwipeAction) {
        deck.removeAll { $0.profileCard?.uid == card.uid }
        swipedUids.insert(card.uid)
        lastSwipedProfile = card
        reportTopImpressionIfNeeded()
        Task {
            do {
                let result: SwipeResult = try await APIClient.shared.post(
                    "/api/swipes/\(card.uid)",
                    body: SwipeIn(action: action)
                )
                if action != .pass, result.isMatch {
                    matchedCard = card
                    // A match can't be undone (the server refuses), so drop
                    // the undo affordance rather than offer a dead button.
                    if lastSwipedProfile?.uid == card.uid { lastSwipedProfile = nil }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            if deck.count <= 3 {
                await fetchMore()
            }
        }
    }

    /// Rewind: forget the last swipe on the server and put the card back on top.
    @MainActor
    func undoLastSwipe() {
        guard let card = lastSwipedProfile else { return }
        lastSwipedProfile = nil
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.delete("/api/swipes/\(card.uid)")
                swipedUids.remove(card.uid)
                deck.removeAll { $0.profileCard?.uid == card.uid }
                deck.insert(.profile(card), at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// A sponsored card was swiped. Liking opens the link in the in-app
    /// browser; either way the card leaves the deck and no swipe is recorded.
    @MainActor
    func swipeAd(_ ad: AdCard, liked: Bool) {
        deck.removeAll { $0.id == "ad-\(ad.adId)" }
        reportTopImpressionIfNeeded()
        if liked, let url = ad.url {
            urlToOpen = url
            reportContentEvent(path: "ads/\(ad.adId)", event: "click")
        }
        refillIfLow()
    }

    /// A news card was swiped. Liking opens the source article in the in-app
    /// browser — never the phone's browser; either way no swipe is recorded.
    @MainActor
    func swipeNews(_ item: NewsCard, liked: Bool) {
        deck.removeAll { $0.id == "news-\(item.newsId)" }
        reportTopImpressionIfNeeded()
        if liked, let url = item.url {
            urlToOpen = url
            reportContentEvent(path: "news/\(item.newsId)", event: "click")
        }
        refillIfLow()
    }

    /// A community post was swiped. Liking an event RSVPs (the "like"
    /// gesture reads as "I'm coming"); liking anything else opens its link if
    /// it has one (announcements and polls don't). Either way no swipe is
    /// recorded and the card leaves the deck immediately.
    @MainActor
    func swipePost(_ post: CommunityPostCard, liked: Bool) {
        deck.removeAll { $0.id == "post-\(post.postId)" }
        reportTopImpressionIfNeeded()
        if liked {
            if post.kind == "event" {
                Task { _ = await rsvp(on: post, going: true) }
            } else if let url = post.url {
                urlToOpen = url
                reportContentEvent(path: "posts/\(post.postId)", event: "click")
            }
        }
        refillIfLow()
    }

    private func refillIfLow() {
        if deck.count <= 3 {
            Task { await fetchMore() }
        }
    }

    /// Call whenever the deck's top card may have changed; reports one
    /// impression per content card per session the first time it surfaces.
    @MainActor
    func reportTopImpressionIfNeeded() {
        let path: String
        switch deck.first {
        case .ad(let ad):
            guard !impressedContentIds.contains(ad.id) else { return }
            impressedContentIds.insert(ad.id)
            path = "ads/\(ad.adId)"
        case .news(let item):
            guard !impressedContentIds.contains(item.id) else { return }
            impressedContentIds.insert(item.id)
            path = "news/\(item.newsId)"
        case .post(let post):
            guard !impressedContentIds.contains(post.id) else { return }
            impressedContentIds.insert(post.id)
            path = "posts/\(post.postId)"
        case .profile, nil:
            return
        }
        reportContentEvent(path: path, event: "impression")
    }

    private func reportContentEvent(path: String, event: String) {
        Task {
            // Fire-and-forget analytics; failures must never surface to the user.
            let _: EmptyResponse? = try? await APIClient.shared.post(
                "/api/\(path)/events",
                body: ContentEventIn(event: event)
            )
        }
    }

    /// Casts (or changes) a vote on a poll post, updating the matching deck
    /// entry so the change survives dismissing and re-showing the card.
    /// Returns the updated post for the caller to refresh its own local copy.
    @MainActor
    func vote(on post: CommunityPostCard, optionId: String) async -> CommunityPostCard? {
        do {
            let result: VoteResult = try await APIClient.shared.post(
                "/api/posts/\(post.postId)/vote",
                body: VoteIn(optionId: optionId)
            )
            var updated = post
            updated.poll = result.poll
            updated.myVote = result.myVote
            if let index = deck.firstIndex(where: { $0.id == "post-\(post.postId)" }) {
                deck[index] = .post(updated)
            }
            return updated
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// RSVPs (or cancels) for an event post, updating the matching deck entry
    /// so the change survives dismissing and re-showing the card. Returns the
    /// updated post for the caller to refresh its own local copy.
    @MainActor
    func rsvp(on post: CommunityPostCard, going: Bool) async -> CommunityPostCard? {
        do {
            let result: RsvpResult = going
                ? try await APIClient.shared.post("/api/posts/\(post.postId)/rsvp")
                : try await APIClient.shared.delete("/api/posts/\(post.postId)/rsvp")
            var updated = post
            updated.attendeeCount = result.attendeeCount
            updated.myRsvp = result.going
            if let index = deck.firstIndex(where: { $0.id == "post-\(post.postId)" }) {
                deck[index] = .post(updated)
            }
            return updated
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func reportAndRemove(_ card: FeedCard, reason: String) {
        deck.removeAll { $0.profileCard?.uid == card.uid }
        reportTopImpressionIfNeeded()
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/reports",
                    body: ReportIn(reportedUid: card.uid, reason: reason, note: "")
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func blockAndRemove(_ card: FeedCard) {
        deck.removeAll { $0.profileCard?.uid == card.uid }
        reportTopImpressionIfNeeded()
        Task {
            do {
                let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(card.uid)")
                BlockStore.shared.record(uid: card.uid, displayName: card.displayName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
