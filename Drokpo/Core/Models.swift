import Foundation

// NOTE: The backend's OpenAPI spec declares empty response schemas, so every
// response field here is optional and decoded defensively. Verify against the
// live API and tighten as the contract firms up.

struct GeoLocation: Codable, Equatable {
    var lat: Double
    var lng: Double
}

struct Preferences: Codable, Equatable {
    var ageMin: Int = 18
    var ageMax: Int = 99
    var distanceKm: Int = 50
}

/// Social handles. Instagram is the one handle every profile must have; the
/// backend rejects onboarding without it and never lets it be cleared.
struct Socials: Codable, Equatable {
    var instagram: String?
    var youtube: String?
    var tiktok: String?
    var facebook: String?
    var x: String?
    var wechat: String?
}

struct Photo: Codable, Equatable, Identifiable, Hashable {
    var storagePath: String
    var order: Int?
    var url: String?

    var id: String { storagePath }
}

struct Profile: Codable, Equatable, Identifiable {
    var uid: String?
    var displayName: String?
    var dob: String?
    var gender: String?
    var bio: String?
    var occupation: String?
    var education: String?
    var region: String?
    var languages: [String]?
    var interests: [String]?
    var answers: [String: String]?
    var socials: Socials?
    var photos: [Photo]?
    var preferences: Preferences?
    var onboardingComplete: Bool?

    var id: String { uid ?? "me" }

    var age: Int? {
        guard let dob, let date = Self.dobFormatter.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }

    static let dobFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Your own profile shaped as the card other members see, for previewing.
    var asFeedCard: FeedCard {
        FeedCard(
            uid: uid ?? "me",
            displayName: displayName,
            age: age,
            dob: dob,
            region: region,
            bio: bio,
            occupation: occupation,
            education: education,
            languages: languages,
            interests: interests,
            answers: answers,
            socials: socials,
            photos: photos
        )
    }
}

struct FeedCard: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String?
    var age: Int?
    var dob: String?
    var region: String?
    var bio: String?
    var occupation: String?
    var education: String?
    var languages: [String]?
    var interests: [String]?
    var answers: [String: String]?
    var socials: Socials?
    var photos: [Photo]?
    var distanceKm: Double?

    var id: String { uid }

    var displayAge: Int? {
        if let age { return age }
        guard let dob, let date = Profile.dobFormatter.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }
}

/// A sponsored card served with the feed (see backend docs/ADS.md). Shown in
/// the Discover deck after every few real profiles; liking it opens `linkUrl`
/// in the in-app browser instead of recording a swipe.
struct AdCard: Codable, Equatable, Identifiable {
    var adId: String
    var title: String?
    var body: String?
    var linkUrl: String?
    var ctaLabel: String?
    var imageUrl: String?
    var photos: [Photo]?

    var id: String { adId }

    var url: URL? { linkUrl.flatMap(URL.init(string:)) }

    /// Creative to render — `photos` if present, else `imageUrl` wrapped as a
    /// single photo (the synthetic storagePath only serves as a cache key).
    var displayPhotos: [Photo] {
        if let photos, !photos.isEmpty { return photos }
        if let imageUrl { return [Photo(storagePath: "ad-image-\(adId)", order: 0, url: imageUrl)] }
        return []
    }
}

/// GET /api/feed response: real profiles plus the active sponsored cards.
struct FeedResponse: Decodable {
    var candidates: [FeedCard]?
    var ads: [AdCard]?
}

struct LastMessage: Codable, Equatable {
    var text: String?
    var senderId: String?
}

struct Match: Codable, Equatable, Identifiable {
    var matchId: String?
    var users: [String]?
    var status: String?
    var otherUser: FeedCard?
    var lastMessage: LastMessage?
    var unreadCount: [String: Int]?
    var createdAt: String?

    var id: String { matchId ?? otherUser?.uid ?? UUID().uuidString }

    func unread(for uid: String?) -> Int {
        guard let uid else { return 0 }
        return unreadCount?[uid] ?? 0
    }
}

/// One entry from GET /api/swipes or GET /api/swipes/received.
struct SwipeEntry: Codable, Equatable, Identifiable {
    var uid: String?
    var action: String?
    var createdAt: String?
    var otherUser: FeedCard?
    var matchId: String?
    var matchStatus: String?

    var id: String { uid ?? otherUser?.uid ?? UUID().uuidString }
    var isMatched: Bool { matchId != nil }
}

struct SwipeResult: Codable {
    var matched: Bool?
    var matchId: String?
    var match: Match?

    var isMatch: Bool { matched ?? (matchId != nil || match != nil) }
}

/// One entry from GET /api/messages/sent.
struct SentMessage: Codable, Equatable, Identifiable {
    var messageId: String?
    var matchId: String?
    var senderId: String?
    var text: String?
    var createdAt: String?

    var id: String { messageId ?? UUID().uuidString }

    var sentDate: Date? {
        guard let createdAt else { return nil }
        return Self.isoFormatter.date(from: createdAt) ?? Self.isoFractionalFormatter.date(from: createdAt)
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// The spec doesn't say whether list endpoints return a bare array or a wrapper
/// object, so accept both shapes.
struct TolerantList<Element: Decodable>: Decodable {
    var items: [Element]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var collected: [Element] = []
            while !unkeyed.isAtEnd {
                collected.append(try unkeyed.decode(Element.self))
            }
            items = collected
            return
        }
        let keyed = try decoder.container(keyedBy: AnyKey.self)
        for key in keyed.allKeys {
            if let list = try? keyed.decode([Element].self, forKey: key) {
                items = list
                return
            }
        }
        items = []
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

// MARK: - Request bodies

struct OnboardingIn: Encodable {
    var displayName: String
    var dob: String
    var gender: String?
    var bio: String
    var occupation: String
    var education: String
    var region: String
    var languages: [String]
    var interests: [String]
    var answers: [String: String]
    var socials: Socials
    var location: GeoLocation
    var preferences: Preferences
}

struct PhotoConfirm: Encodable {
    var storagePath: String
    var order: Int
}

struct PhotoOrderUpdate: Encodable {
    var storagePaths: [String]
}

struct ProfileUpdate: Encodable {
    var displayName: String?
    var bio: String?
    var dob: String?
    var gender: String?
    var occupation: String?
    var education: String?
    var region: String?
    var languages: [String]?
    var interests: [String]?
    var answers: [String: String]?
    var socials: Socials?
    var location: GeoLocation?
    var preferences: Preferences?
}

struct SwipeIn: Encodable {
    var action: SwipeAction
}

enum SwipeAction: String, Encodable {
    case like, pass, superlike
}

struct MessageIn: Encodable {
    var text: String
}

struct FcmTokenIn: Encodable {
    var token: String
}

struct ReportIn: Encodable {
    var reportedUid: String
    var reason: String
    var note: String
}

/// POST /api/ads/{adId}/events — fire-and-forget ad analytics.
struct AdEventIn: Encodable {
    var event: String // "impression" | "click"
}

// MARK: - Profile questions

/// A profile prompt shown during onboarding/editing and rendered on the
/// profile detail card. `key` is the stable id stored in the profile's
/// `answers` map — never change a key once shipped.
struct ProfileQuestion: Identifiable {
    enum Kind {
        case choice([String])
        case text(placeholder: String)
    }

    let key: String
    let label: String
    let kind: Kind

    var id: String { key }
}

// MARK: - Shared vocabulary

enum Vocabulary {
    static let genders = ["male", "female"]
    static let regions = [
        "India", "Nepal", "Bhutan",
        "North America", "Europe", "Australia", "Other",
    ]
    static let languages = ["Tibetan", "English", "Hindi", "Nepali", "Mandarin", "French", "German", "Other"]
    static let interests = [
        "Momo cooking", "Gorshey", "Hiking", "Music", "Photography",
        "Reading", "Meditation", "Thangka painting", "Basketball", "Soccer",
        "Movies", "Travel", "Board games", "Volunteering",
        "Cooking", "Dancing", "Singing", "Art & design", "Gaming",
        "Cricket", "Chess", "Fitness", "Buddhism & philosophy", "Language exchange",
    ]
    static let educationLevels = [
        "High school", "Some college", "Bachelor's", "Master's", "PhD",
        "Monastic education", "Other",
    ]
    /// Friendship-flavoured prompts; all optional. Answers live in the
    /// profile's `answers` map keyed by `ProfileQuestion.key`.
    static let questions: [ProfileQuestion] = [
        .init(key: "lookingFor", label: "I'm here for", kind: .choice([
            "New friends", "Dating", "Friends first, then who knows", "Community & events",
        ])),
        .init(key: "teaChoice", label: "Chai or butter tea?", kind: .choice([
            "Chai", "Butter tea", "Both, please", "Coffee person",
        ])),
        .init(key: "travelledTo", label: "Places I've travelled to", kind: .text(
            placeholder: "Dharamshala, Kathmandu, New York…"
        )),
        .init(key: "favoriteMovies", label: "Movies I can rewatch forever", kind: .text(
            placeholder: "Your comfort films"
        )),
        .init(key: "favoriteMusic", label: "Songs on repeat", kind: .text(
            placeholder: "Artists or songs you love right now"
        )),
        .init(key: "perfectWeekend", label: "My perfect weekend", kind: .text(
            placeholder: "Hiking? Momo party? Netflix?"
        )),
    ]
    static let reportReasons = ["Fake profile", "Inappropriate photos", "Harassment", "Spam", "Underage", "Other"]

    /// Rough fallback coordinates per region for users who decline location access.
    static let regionCoordinates: [String: GeoLocation] = [
        "India": .init(lat: 32.22, lng: 76.32),
        "Nepal": .init(lat: 27.72, lng: 85.32),
        "Bhutan": .init(lat: 27.47, lng: 89.64),
        "North America": .init(lat: 40.71, lng: -74.0),
        "Europe": .init(lat: 47.37, lng: 8.54),
        "Australia": .init(lat: -33.87, lng: 151.21),
        "Other": .init(lat: 0, lng: 0),
    ]
}
