import Foundation

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case movie
    case episode
    case special
}

enum CollectionKind: String, Codable, Sendable {
    case films
    case series
    case queue
    case placeholder
}

enum WatchQueueStatus: String, Codable, CaseIterable, Sendable {
    case watching
    case nextUp

    var title: String { self == .watching ? "Watching" : "Next Up" }
    var symbol: String { self == .watching ? "play.circle.fill" : "pin.fill" }
}

struct ProviderLink: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var provider: String
    var url: String
    var accessType: String? = nil
    var price: Double? = nil
    var format: String? = nil

    var isIncluded: Bool { accessType == nil || accessType == "sub" || accessType == "free" }

    var actionLabel: String {
        let priceText = price.map { String(format: "$%.2f", $0) }
        switch accessType {
        case "free": return "Watch free on \(provider)"
        case "rent": return "Rent\(priceText.map { " \($0)" } ?? "") on \(provider)"
        case "buy": return "Buy\(priceText.map { " \($0)" } ?? "") on \(provider)"
        default: return "Watch on \(provider)"
        }
    }
}

struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var kind: MediaKind
    var seriesTitle: String?
    var season: Int?
    var episode: Int?
    var releaseYear: Int?
    var airDate: String?
    var runtimeMinutes: Int
    var providerLinks: [ProviderLink]
    var artworkURL: String? = nil
    var publicRating: Double? = nil
    var criticScore: Int? = nil
    var contentRating: String? = nil
    var queueStatus: WatchQueueStatus? = nil
    var pinnedAt: Double? = nil
}

struct WatchOrder: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var itemIDs: [String]
}

struct ExternalSource: Codable, Hashable, Sendable {
    var provider: String
    var id: String
    var url: String?
    var lastSyncedAt: Double?
}

struct MediaCollection: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var subtitle: String
    var kind: CollectionKind
    var symbol: String
    var accent: String
    var position: Int
    var orders: [WatchOrder]
    var externalSource: ExternalSource? = nil
    var artworkURL: String? = nil
}

struct WatchEvent: Codable, Hashable, Identifiable {
    var id: String
    var itemID: String
    var watchedAt: Double
    var source: String
}

struct ViewingSession: Codable, Hashable, Identifiable {
    var id: String
    var itemID: String
    var watchedAt: Double
    var minutesWatched: Int
    var endingPositionMinutes: Int
    var note: String?
    var source: String
    var watchEventID: String?
}

struct RatingEntry: Codable, Hashable, Identifiable {
    var id: String
    var itemID: String
    var watchEventID: String
    var person: String
    var stars: Double
    var ratedAt: Double
}

struct AuditEntry: Codable, Hashable, Identifiable {
    var id: String
    var timestamp: Double
    var source: String
    var action: String
}

struct LibraryData: Codable, Equatable {
    var schemaVersion: Int
    var setupComplete: Bool?
    var profiles: [String]
    var subscribedProviders: [String]?
    var collections: [MediaCollection]
    var items: [MediaItem]
    var watchEvents: [WatchEvent]
    var ratings: [RatingEntry]
    var viewingSessions: [ViewingSession]?
    var auditLog: [AuditEntry]

    static let empty = LibraryData(
        schemaVersion: 8,
        setupComplete: nil,
        profiles: ["Person 1", "Person 2"],
        subscribedProviders: nil,
        collections: [],
        items: [],
        watchEvents: [],
        ratings: [],
        viewingSessions: [],
        auditLog: []
    )
}

struct StreamingServiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let color: String

    static let catalog: [StreamingServiceOption] = [
        .init(id: "Disney+", name: "Disney+", symbol: "sparkles.tv", color: "1261D7"),
        .init(id: "Prime Video", name: "Prime Video", symbol: "shippingbox.fill", color: "00A8E1"),
        .init(id: "Peacock", name: "Peacock", symbol: "circle.hexagongrid.fill", color: "F4A623"),
        .init(id: "Paramount+", name: "Paramount+", symbol: "mountain.2.fill", color: "0064FF"),
        .init(id: "Netflix", name: "Netflix", symbol: "n.square.fill", color: "E50914"),
        .init(id: "Hulu", name: "Hulu", symbol: "h.square.fill", color: "1CE783"),
        .init(id: "Max", name: "Max", symbol: "m.square.fill", color: "5B3DF5"),
        .init(id: "Apple TV+", name: "Apple TV+", symbol: "apple.logo", color: "777777"),
        .init(id: "Crunchyroll", name: "Crunchyroll", symbol: "play.circle.fill", color: "F47521"),
        .init(id: "AMC+", name: "AMC+", symbol: "a.square.fill", color: "B7212D"),
        .init(id: "STARZ", name: "STARZ", symbol: "star.square.fill", color: "6B5CFF"),
        .init(id: "MGM+", name: "MGM+", symbol: "m.square.fill", color: "C9A227"),
        .init(id: "Shudder", name: "Shudder", symbol: "eye.fill", color: "C6172C"),
        .init(id: "BritBox", name: "BritBox", symbol: "b.square.fill", color: "E6248F"),
        .init(id: "The Criterion Channel", name: "Criterion Channel", symbol: "c.square.fill", color: "888888"),
        .init(id: "Tubi", name: "Tubi · Free", symbol: "play.square.stack.fill", color: "FF4C00"),
        .init(id: "The Roku Channel", name: "Roku Channel · Free", symbol: "tv.fill", color: "6C3C97"),
        .init(id: "Pluto TV", name: "Pluto TV · Free", symbol: "globe.americas.fill", color: "FFD600"),
        .init(id: "Plex", name: "Plex · Free", symbol: "play.rectangle.fill", color: "E5A00D"),
        .init(id: "Kanopy", name: "Kanopy · Library", symbol: "books.vertical.fill", color: "22A9E0"),
        .init(id: "Hoopla", name: "Hoopla · Library", symbol: "building.columns.fill", color: "0073CF")
    ]
}

struct EpisodeSeed: Codable {
    var id: String
    var title: String
    var season: Int
    var episode: Int
    var airDate: String?
}

extension Array where Element == MediaItem {
    func byID(_ id: String) -> MediaItem? { first { $0.id == id } }
}
