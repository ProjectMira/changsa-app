import Foundation

/// One card in the Discover deck: a real member, or a sponsored card.
enum DeckItem: Equatable, Identifiable {
    case profile(FeedCard)
    case ad(AdCard)

    var id: String {
        switch self {
        case .profile(let card): "profile-\(card.uid)"
        case .ad(let ad): "ad-\(ad.adId)"
        }
    }

    var profileCard: FeedCard? {
        if case .profile(let card) = self { return card }
        return nil
    }
}

@Observable
final class FeedModel {
    /// How many real profiles appear between sponsored cards.
    static let profilesPerAd = 3

    var deck: [DeckItem] = []
    var isLoading = false
    var matchedCard: FeedCard?
    var errorMessage: String?
    /// Ad whose link is currently open in the in-app browser sheet.
    var adToOpen: AdCard?
    /// The last profile swiped this session, undoable until the next swipe.
    /// Cleared on match (undo is refused server-side once matched).
    private(set) var lastSwipedProfile: FeedCard?

    var canUndo: Bool { lastSwipedProfile != nil }

    private var isFetching = false
    /// Everyone swiped this session. The backend also filters swiped users,
    /// but a feed fetch that races an in-flight swipe POST can still return
    /// someone we just swiped — never re-add them.
    private var swipedUids: Set<String> = []
    /// Active ads from the last feed response, inserted round-robin.
    private var ads: [AdCard] = []
    private var adCursor = 0
    /// Profiles appended since an ad was last inserted.
    private var profilesSinceAd = 0
    /// Ads whose impression we already reported this session.
    private var impressedAdIds: Set<String> = []

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
            let known = Set(deck.compactMap { $0.profileCard?.uid })
            let fresh = (response.candidates ?? []).filter {
                !known.contains($0.uid) && !swipedUids.contains($0.uid)
            }
            appendInterleaving(fresh)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends profiles to the deck, inserting one sponsored card after every
    /// `profilesPerAd` real profiles (when an ad not already in the deck is
    /// available).
    @MainActor
    private func appendInterleaving(_ profiles: [FeedCard]) {
        for card in profiles {
            deck.append(.profile(card))
            profilesSinceAd += 1
            if profilesSinceAd >= Self.profilesPerAd, let ad = nextAd() {
                deck.append(.ad(ad))
                profilesSinceAd = 0
            }
        }
        reportTopImpressionIfNeeded()
    }

    /// Next active ad, round-robin, skipping any already sitting in the deck.
    private func nextAd() -> AdCard? {
        guard !ads.isEmpty else { return nil }
        let inDeck = Set(deck.compactMap { item -> String? in
            if case .ad(let ad) = item { return ad.adId }
            return nil
        })
        for _ in 0..<ads.count {
            let ad = ads[adCursor % ads.count]
            adCursor += 1
            if !inDeck.contains(ad.adId) { return ad }
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
        if liked, ad.url != nil {
            adToOpen = ad
            reportAdEvent(ad, event: "click")
        }
        if deck.count <= 3 {
            Task { await fetchMore() }
        }
    }

    /// Call whenever the deck's top card may have changed; reports one
    /// impression per ad per session the first time it surfaces.
    @MainActor
    func reportTopImpressionIfNeeded() {
        guard case .ad(let ad) = deck.first, !impressedAdIds.contains(ad.adId) else { return }
        impressedAdIds.insert(ad.adId)
        reportAdEvent(ad, event: "impression")
    }

    private func reportAdEvent(_ ad: AdCard, event: String) {
        Task {
            // Fire-and-forget analytics; failures must never surface to the user.
            let _: EmptyResponse? = try? await APIClient.shared.post(
                "/api/ads/\(ad.adId)/events",
                body: AdEventIn(event: event)
            )
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
