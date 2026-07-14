import Foundation
import Security

@MainActor
enum WatchmodeKeychain {
    private static let service = "com.nextup.app.watchmode"
    private static let account = "api-key"
    private static var cachedKey: String?
    private static var hasLoaded = false

    static func load() -> String? {
        if hasLoaded { return cachedKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        hasLoaded = true
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        cachedKey = String(data: data, encoding: .utf8)
        return cachedKey
    }

    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let data = clean.data(using: .utf8) else { throw WatchmodeError.emptyKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw WatchmodeError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw WatchmodeError.keychain(status)
        }
        cachedKey = clean
        hasLoaded = true
    }

    static func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WatchmodeError.keychain(status) }
        cachedKey = nil
        hasLoaded = true
    }
}

struct WatchmodeAvailabilityUpdate: Sendable {
    let itemID: String
    let provider: String
    let url: String
    let accessType: String?
    let price: Double?
    let format: String?
}

struct WatchmodeSyncResult: Sendable {
    var updates: [WatchmodeAvailabilityUpdate] = []
    var metadataUpdates: [WatchmodeMediaMetadataUpdate] = []
    var matchedTitles = 0
    var checkedTitles = 0
    var warnings: [String] = []

    var linkedItemCount: Int { Set(updates.map(\.itemID)).count }
}

struct WatchmodeMediaMetadataUpdate: Sendable {
    let itemID: String
    let artworkURL: String?
    let runtimeMinutes: Int?
    let publicRating: Double?
    let criticScore: Int?
    let contentRating: String?

    init(itemID: String, artworkURL: String?, runtimeMinutes: Int?, publicRating: Double? = nil, criticScore: Int? = nil, contentRating: String? = nil) {
        self.itemID = itemID
        self.artworkURL = artworkURL
        self.runtimeMinutes = runtimeMinutes
        self.publicRating = publicRating
        self.criticScore = criticScore
        self.contentRating = contentRating
    }
}

struct WatchmodeMovieSearchResult: Identifiable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let artworkURL: String?
}

struct WatchmodeMovieImport: Sendable {
    let watchmodeID: Int
    let title: String
    let year: Int?
    let runtimeMinutes: Int
    let artworkURL: String?
    let providerLinks: [ProviderLink]
    let publicRating: Double?
    let criticScore: Int?
    let contentRating: String?

    init(watchmodeID: Int, title: String, year: Int?, runtimeMinutes: Int, artworkURL: String?, providerLinks: [ProviderLink], publicRating: Double? = nil, criticScore: Int? = nil, contentRating: String? = nil) {
        self.watchmodeID = watchmodeID
        self.title = title
        self.year = year
        self.runtimeMinutes = runtimeMinutes
        self.artworkURL = artworkURL
        self.providerLinks = providerLinks
        self.publicRating = publicRating
        self.criticScore = criticScore
        self.contentRating = contentRating
    }
}

enum WatchmodeService {
    /// Checks the user's library against Watchmode. Movies are matched individually;
    /// series are matched once and their episode-level sources are applied by S/E number.
    static func availability(
        key: String,
        collections: [MediaCollection],
        items: [MediaItem]
    ) async throws -> WatchmodeSyncResult {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw WatchmodeError.emptyKey }

        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result = WatchmodeSyncResult()

        // An item may appear in more than one viewing order. Only spend API quota once.
        let movieIDs = Set(collections.flatMap { $0.orders.flatMap(\.itemIDs) })
        let movies = movieIDs.compactMap { itemsByID[$0] }.filter { $0.kind == .movie || $0.kind == .special }
        for movie in movies.sorted(by: { $0.title < $1.title }) {
            result.checkedTitles += 1
            do {
                let titleID: Int
                if let knownID = watchmodeID(from: movie.id) {
                    titleID = knownID
                } else if let match = try await bestMatch(
                    name: movieSearchName(movie),
                    year: movie.releaseYear,
                    expected: .movie,
                    key: cleanKey
                ) {
                    titleID = match.id
                } else {
                    result.warnings.append("No match for \(movie.title)")
                    continue
                }
                let details = try await titleDetails(titleID: titleID, includeSources: true, key: cleanKey)
                let links = supportedLinks(in: details.sources ?? [])
                if !links.isEmpty { result.matchedTitles += 1 }
                result.updates += links.map { .init(itemID: movie.id, provider: $0.provider, url: $0.url, accessType: $0.accessType, price: $0.price, format: $0.format) }
                result.metadataUpdates.append(.init(
                    itemID: movie.id,
                    artworkURL: details.preferredPoster,
                    runtimeMinutes: details.runtimeMinutes,
                    publicRating: details.userRating,
                    criticScore: details.criticScore,
                    contentRating: details.contentRating
                ))
            } catch {
                if shouldStop(error) { throw error }
                result.warnings.append("\(movie.title): \(error.localizedDescription)")
            }
        }

        let seriesCollections = collections.filter { collection in
            collection.kind == .series && collection.orders.flatMap(\.itemIDs).contains {
                itemsByID[$0]?.kind == .episode
            }
        }
        for collection in seriesCollections {
            let episodes = collection.orders.flatMap(\.itemIDs)
                .compactMap { itemsByID[$0] }
                .filter { $0.kind == .episode }
            guard !episodes.isEmpty else { continue }
            let seriesName = episodes.compactMap(\.seriesTitle).first ?? collection.name
            let seriesYear = episodes.compactMap(\.releaseYear).min()
            result.checkedTitles += 1
            do {
                guard let match = try await bestMatch(
                    name: seriesName,
                    year: seriesYear,
                    expected: .series,
                    key: cleanKey
                ) else {
                    result.warnings.append("No match for \(seriesName)")
                    continue
                }

                do {
                    let remoteEpisodes = try await titleEpisodes(titleID: match.id, key: cleanKey)
                    let remoteByNumber = Dictionary(grouping: remoteEpisodes) {
                        "\($0.seasonNumber)-\($0.episodeNumber)"
                    }
                    var foundSeriesLink = false
                    for episode in episodes {
                        guard let season = episode.season, let number = episode.episode,
                              let remote = remoteByNumber["\(season)-\(number)"]?.first else { continue }
                        let links = supportedLinks(in: remote.sources)
                        if !links.isEmpty { foundSeriesLink = true }
                        result.updates += links.map { .init(itemID: episode.id, provider: $0.provider, url: $0.url, accessType: $0.accessType, price: $0.price, format: $0.format) }
                    }
                    if foundSeriesLink { result.matchedTitles += 1 }
                } catch {
                    if shouldStop(error) { throw error }
                    // Some plans/titles do not expose episode detail. A series-level
                    // source is still more useful than showing no availability at all.
                    let sources = try await titleSources(titleID: match.id, key: cleanKey)
                    let links = supportedLinks(in: sources)
                    if !links.isEmpty { result.matchedTitles += 1 }
                    for episode in episodes {
                        result.updates += links.map { .init(itemID: episode.id, provider: $0.provider, url: $0.url, accessType: $0.accessType, price: $0.price, format: $0.format) }
                    }
                }
            } catch {
                if shouldStop(error) { throw error }
                result.warnings.append("\(seriesName): \(error.localizedDescription)")
            }
        }

        return result
    }

    static func test(key: String) async throws {
        let request = try request(path: "status/", key: key)
        _ = try await fetch(request)
    }

    static func searchMovies(query: String, key: String) async throws -> [WatchmodeMovieSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        let request = try request(
            path: "autocomplete-search/",
            query: [
                URLQueryItem(name: "search_value", value: clean),
                URLQueryItem(name: "search_type", value: "3")
            ],
            key: key
        )
        let data = try await fetch(request)
        let response = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
        return response.results
            .filter { $0.type == "movie" || $0.type == "tv_movie" }
            .prefix(30)
            .map { .init(id: $0.id, title: $0.name, year: $0.year, artworkURL: $0.imageURL) }
    }

    static func movieDetails(id: Int, key: String) async throws -> WatchmodeMovieImport {
        let details = try await titleDetails(titleID: id, includeSources: true, key: key)
        return try movieImport(titleID: id, details: details)
    }

    static func movieSuggestions(seed: MediaItem?, key: String, limit: Int = 8) async throws -> [WatchmodeMovieSearchResult] {
        let seedID: Int?
        if let seed {
            if let known = watchmodeID(from: seed.id) {
                seedID = known
            } else {
                seedID = try await bestMatch(name: movieSearchName(seed), year: seed.releaseYear, expected: .movie, key: key)?.id
            }
        } else {
            seedID = nil
        }

        var candidateIDs: [Int] = []
        if let seedID {
            candidateIDs = try await titleDetails(titleID: seedID, includeSources: false, key: key).similarTitles ?? []
        }
        if candidateIDs.isEmpty {
            let request = try request(
                path: "list-titles/",
                query: [
                    URLQueryItem(name: "types", value: "movie"),
                    URLQueryItem(name: "regions", value: "US"),
                    URLQueryItem(name: "sort_by", value: "popularity_desc"),
                    URLQueryItem(name: "limit", value: String(max(12, limit)))
                ],
                key: key
            )
            let data = try await fetch(request)
            candidateIDs = try JSONDecoder().decode(TitleListResponse.self, from: data).titles.map(\.id)
        }

        var suggestions: [WatchmodeMovieSearchResult] = []
        for id in candidateIDs where suggestions.count < limit {
            guard let details = try? await titleDetails(titleID: id, includeSources: false, key: key),
                  details.type == "movie" || details.type == "tv_movie" else { continue }
            suggestions.append(.init(id: id, title: details.title, year: details.year, artworkURL: details.preferredPoster))
        }
        return suggestions
    }

    private static func movieImport(titleID id: Int, details: TitleDetails) throws -> WatchmodeMovieImport {
        guard details.type == "movie" || details.type == "tv_movie" else { throw WatchmodeError.notMovie }
        let links = supportedLinks(in: details.sources ?? []).map {
            ProviderLink(id: UUID().uuidString, provider: $0.provider, url: $0.url, accessType: $0.accessType, price: $0.price, format: $0.format)
        }
        return WatchmodeMovieImport(
            watchmodeID: id,
            title: details.title,
            year: details.year,
            runtimeMinutes: max(1, details.runtimeMinutes ?? 120),
            artworkURL: details.preferredPoster,
            providerLinks: links,
            publicRating: details.userRating,
            criticScore: details.criticScore,
            contentRating: details.contentRating
        )
    }

    private enum ExpectedTitle { case movie, series }

    private struct SearchResponse: Decodable {
        let titleResults: [SearchResult]
        enum CodingKeys: String, CodingKey { case titleResults = "title_results" }
    }

    private struct SearchResult: Decodable {
        let id: Int
        let name: String
        let type: String
        let year: Int?
    }

    private struct AutocompleteResponse: Decodable {
        let results: [AutocompleteResult]
    }

    private struct AutocompleteResult: Decodable {
        let id: Int
        let name: String
        let type: String
        let year: Int?
        let imageURL: String?
        enum CodingKeys: String, CodingKey {
            case id, name, type, year
            case imageURL = "image_url"
        }
    }

    private struct Source: Decodable {
        let name: String
        let type: String
        let region: String?
        let webURL: String?
        let price: Double?
        let format: String?
        enum CodingKeys: String, CodingKey {
            case name, type, region, price, format
            case webURL = "web_url"
        }
    }

    private struct Episode: Decodable {
        let episodeNumber: Int
        let seasonNumber: Int
        let sources: [Source]
        enum CodingKeys: String, CodingKey {
            case episodeNumber = "episode_number"
            case seasonNumber = "season_number"
            case sources
        }
    }

    private struct TitleDetails: Decodable {
        let title: String
        let type: String
        let year: Int?
        let runtimeMinutes: Int?
        let poster: String?
        let posterMedium: String?
        let posterLarge: String?
        let sources: [Source]?
        let similarTitles: [Int]?
        let userRating: Double?
        let criticScore: Int?
        let contentRating: String?

        enum CodingKeys: String, CodingKey {
            case title, type, year, poster, posterMedium, posterLarge, sources
            case runtimeMinutes = "runtime_minutes"
            case similarTitles = "similar_titles"
            case userRating = "user_rating"
            case criticScore = "critic_score"
            case contentRating = "us_rating"
        }

        var preferredPoster: String? { posterMedium ?? poster ?? posterLarge }
    }

    private struct SupportedLink {
        let provider: String
        let url: String
        let accessType: String
        let price: Double?
        let format: String?
    }

    private struct TitleListResponse: Decodable {
        struct Entry: Decodable { let id: Int }
        let titles: [Entry]
    }

    private static func bestMatch(
        name: String,
        year: Int?,
        expected: ExpectedTitle,
        key: String
    ) async throws -> SearchResult? {
        let query = [
            URLQueryItem(name: "search_field", value: "name"),
            URLQueryItem(name: "search_value", value: name),
            URLQueryItem(name: "types", value: expected == .movie ? "movie" : "tv")
        ]
        let request = try request(path: "search/", query: query, key: key)
        let data = try await fetch(request)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard !response.titleResults.isEmpty else { return nil }
        return response.titleResults.max { score($0, name: name, year: year, expected: expected) < score($1, name: name, year: year, expected: expected) }
    }

    private static func score(_ candidate: SearchResult, name: String, year: Int?, expected: ExpectedTitle) -> Int {
        let wanted = normalized(name)
        let found = normalized(candidate.name)
        var value = 0
        if wanted == found { value += 120 }
        else if wanted.contains(found) || found.contains(wanted) { value += 55 }
        let wantedWords = Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let foundWords = Set(candidate.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        value += wantedWords.intersection(foundWords).count * 8
        if let year, let candidateYear = candidate.year {
            let difference = abs(year - candidateYear)
            value += difference == 0 ? 45 : difference == 1 ? 18 : max(0, 10 - difference)
        }
        let typeMatches = expected == .movie ? candidate.type.contains("movie") : candidate.type.contains("tv")
        if typeMatches { value += 25 }
        return value
    }

    private static func titleSources(titleID: Int, key: String) async throws -> [Source] {
        let request = try request(
            path: "title/\(titleID)/sources/",
            query: [URLQueryItem(name: "regions", value: "US")],
            key: key
        )
        let data = try await fetch(request)
        return try JSONDecoder().decode([Source].self, from: data)
    }

    private static func titleDetails(titleID: Int, includeSources: Bool, key: String) async throws -> TitleDetails {
        var query: [URLQueryItem] = []
        if includeSources {
            query = [
                URLQueryItem(name: "append_to_response", value: "sources"),
                URLQueryItem(name: "regions", value: "US")
            ]
        }
        let request = try request(path: "title/\(titleID)/details/", query: query, key: key)
        let data = try await fetch(request)
        return try JSONDecoder().decode(TitleDetails.self, from: data)
    }

    private static func titleEpisodes(titleID: Int, key: String) async throws -> [Episode] {
        let request = try request(
            path: "title/\(titleID)/episodes/",
            query: [URLQueryItem(name: "regions", value: "US")],
            key: key
        )
        let data = try await fetch(request)
        return try JSONDecoder().decode([Episode].self, from: data)
    }

    private static func supportedLinks(in sources: [Source]) -> [SupportedLink] {
        var found: [String: SupportedLink] = [:]
        for source in sources where source.region == nil || source.region == "US" {
            guard ["sub", "free", "rent", "buy", "purchase"].contains(source.type),
                  let provider = providerName(for: source.name),
                  let rawURL = source.webURL,
                  let url = URL(string: rawURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let accessType = source.type == "purchase" ? "buy" : source.type
            let key = "\(provider.lowercased())|\(accessType)|\(source.format ?? "")"
            let candidate = SupportedLink(provider: provider, url: rawURL, accessType: accessType, price: source.price, format: source.format)
            if let current = found[key], let oldPrice = current.price, let newPrice = source.price, oldPrice <= newPrice { continue }
            found[key] = candidate
        }
        return Array(found.values).sorted {
            let priority = ["sub": 0, "free": 1, "rent": 2, "buy": 3]
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            if priority[$0.accessType, default: 9] != priority[$1.accessType, default: 9] { return priority[$0.accessType, default: 9] < priority[$1.accessType, default: 9] }
            return ($0.price ?? 0) < ($1.price ?? 0)
        }
    }

    private static func providerName(for watchmodeName: String) -> String? {
        let name = watchmodeName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "disney+", "disney plus": return "Disney+"
        case "prime video", "amazon prime video": return "Prime Video"
        case "peacock", "peacock premium": return "Peacock"
        case "paramount+", "paramount plus": return "Paramount+"
        case "netflix": return "Netflix"
        case "hulu": return "Hulu"
        case "max", "hbo max": return "Max"
        case "appletv+", "apple tv+", "apple tv plus": return "Apple TV+"
        case "tubi", "tubi tv": return "Tubi"
        case "the roku channel", "roku channel": return "The Roku Channel"
        case "amazon": return "Prime Video"
        case "crunchyroll", "crunchyroll premium": return "Crunchyroll"
        case "amc+", "amc plus": return "AMC+"
        case "starz": return "STARZ"
        case "mgm+", "mgm plus": return "MGM+"
        case "shudder": return "Shudder"
        case "britbox": return "BritBox"
        case "the criterion channel", "criterion channel": return "The Criterion Channel"
        case "pluto tv": return "Pluto TV"
        case "plex": return "Plex"
        case "kanopy": return "Kanopy"
        case "hoopla": return "Hoopla"
        default: return nil
        }
    }

    private static func request(path: String, query: [URLQueryItem] = [], key: String) throws -> URLRequest {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw WatchmodeError.emptyKey }
        var components = URLComponents(string: "https://api.watchmode.com/v1/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw WatchmodeError.badResponse }
        var request = URLRequest(url: url)
        // Header authentication prevents the key entering URLs, browser history, or logs.
        request.setValue(clean, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 30
        return request
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WatchmodeError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw WatchmodeError.invalidKey }
        if http.statusCode == 429 { throw WatchmodeError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw WatchmodeError.http(http.statusCode) }
        return data
    }

    private static func shouldStop(_ error: Error) -> Bool {
        guard let error = error as? WatchmodeError else { return false }
        switch error {
        case .invalidKey, .rateLimited: return true
        default: return false
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    private static func movieSearchName(_ movie: MediaItem) -> String {
        // The starter library favors clean display titles, while Watchmode stores
        // the numbered Star Wars movies under their full theatrical names.
        let starterAliases: [String: String] = [
            "sw-new-hope": "Star Wars: Episode IV - A New Hope",
            "sw-empire": "Star Wars: Episode V - The Empire Strikes Back",
            "sw-return": "Star Wars: Episode VI - Return of the Jedi",
            "sw-phantom": "Star Wars: Episode I - The Phantom Menace",
            "sw-clones": "Star Wars: Episode II - Attack of the Clones",
            "sw-sith": "Star Wars: Episode III - Revenge of the Sith",
            "sw-force": "Star Wars: Episode VII - The Force Awakens",
            "sw-last-jedi": "Star Wars: Episode VIII - The Last Jedi",
            "sw-rise": "Star Wars: Episode IX - The Rise of Skywalker",
            "sw-rogue": "Rogue One: A Star Wars Story",
            "sw-solo": "Solo: A Star Wars Story",
            "twilight-4": "The Twilight Saga: Breaking Dawn - Part 1",
            "twilight-5": "The Twilight Saga: Breaking Dawn - Part 2"
        ]
        return starterAliases[movie.id] ?? movie.title
    }

    private static func watchmodeID(from itemID: String) -> Int? {
        guard itemID.hasPrefix("watchmode-movie-") else { return nil }
        return Int(itemID.dropFirst("watchmode-movie-".count))
    }
}

enum WatchmodeError: LocalizedError {
    case emptyKey
    case invalidKey
    case badResponse
    case rateLimited
    case notMovie
    case http(Int)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey: "Enter a Watchmode API key."
        case .invalidKey: "Watchmode rejected this API key."
        case .badResponse: "Watchmode returned an unreadable response."
        case .rateLimited: "Watchmode's request limit was reached. Try again in a minute."
        case .notMovie: "Watchmode did not return a movie for this result."
        case let .http(code): "Watchmode returned HTTP \(code)."
        case let .keychain(status): "macOS Keychain error \(status)."
        }
    }
}
