import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var data: LibraryData = .empty

    let folderURL: URL
    let dataURL: URL
    private let backupURL: URL
    private let lockURL: URL
    private var lastModified: Date = .distantPast

    init(folderURL customFolderURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let environmentFolder = ProcessInfo.processInfo.environment["NEXT_UP_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        folderURL = customFolderURL ?? environmentFolder ?? support.appendingPathComponent("Next Up", isDirectory: true)
        dataURL = folderURL.appendingPathComponent("library.json")
        backupURL = folderURL.appendingPathComponent("library.backup.json")
        lockURL = folderURL.appendingPathComponent("library.lock", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        if let loaded = readDisk() {
            data = loaded
        } else {
            data = SeedFactory.make()
            writeDisk(data, makeBackup: false)
        }
        updateModifiedDate()
        migrateIfNeeded()
    }

    var collections: [MediaCollection] {
        data.collections.sorted { $0.position < $1.position }
    }

    var subscribedProviders: [String] {
        data.subscribedProviders ?? ["Disney+"]
    }

    func availableLinks(for item: MediaItem) -> [ProviderLink] {
        item.providerLinks.filter { link in
            subscribedProviders.contains { $0.caseInsensitiveCompare(link.provider) == .orderedSame }
        }.sorted {
            let priority = ["sub": 0, "free": 1, "rent": 2, "buy": 3]
            let left = priority[$0.accessType ?? "sub", default: 9]
            let right = priority[$1.accessType ?? "sub", default: 9]
            if left != right { return left < right }
            return ($0.price ?? 0) < ($1.price ?? 0)
        }
    }

    func isAvailable(_ item: MediaItem) -> Bool { !availableLinks(for: item).isEmpty }

    func containsMovie(title: String, year: Int?, watchmodeID: Int? = nil) -> Bool {
        if let watchmodeID, data.items.contains(where: { $0.id == "watchmode-movie-\(watchmodeID)" }) { return true }
        return data.items.contains { item in
            item.kind == .movie && item.title.caseInsensitiveCompare(title) == .orderedSame
                && (year == nil || item.releaseYear == nil || item.releaseYear == year)
        }
    }

    func containsSeries(name: String, tvMazeID: Int? = nil) -> Bool {
        data.collections.contains { collection in
            (tvMazeID != nil && collection.externalSource?.provider == "TVmaze" && collection.externalSource?.id == String(tvMazeID!))
                || collection.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func collection(_ id: String) -> MediaCollection? {
        data.collections.first { $0.id == id }
    }

    func orderedItems(collectionID: String, orderID: String? = nil) -> [MediaItem] {
        guard let collection = collection(collectionID) else { return [] }
        let order = collection.orders.first(where: { $0.id == orderID }) ?? collection.orders.first
        return (order?.itemIDs ?? []).compactMap { data.items.byID($0) }
    }

    func nextUnwatched(collectionID: String, orderID: String? = nil) -> MediaItem? {
        prioritizedUnwatchedItems(collectionID: collectionID, orderID: orderID).first
    }

    func prioritizedUnwatchedItems(collectionID: String, orderID: String? = nil) -> [MediaItem] {
        let ordered = orderedItems(collectionID: collectionID, orderID: orderID)
        let originalIndex = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        return ordered.filter { !isWatched($0.id) }.sorted { left, right in
            let leftRank = priorityRank(for: left)
            let rightRank = priorityRank(for: right)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.queueStatus != nil || right.queueStatus != nil {
                let leftDate = left.pinnedAt ?? 0
                let rightDate = right.pinnedAt ?? 0
                if leftDate != rightDate { return leftDate > rightDate }
            }
            return originalIndex[left.id, default: .max] < originalIndex[right.id, default: .max]
        }
    }

    func effectiveQueueStatus(_ item: MediaItem) -> WatchQueueStatus? {
        if isWatched(item.id) { return nil }
        if currentPosition(item.id) > 0 { return .watching }
        return item.queueStatus
    }

    func collectionQueueStatus(_ collectionID: String) -> WatchQueueStatus? {
        let statuses = orderedItems(collectionID: collectionID).compactMap(effectiveQueueStatus)
        if statuses.contains(.watching) { return .watching }
        if statuses.contains(.nextUp) { return .nextUp }
        return nil
    }

    func isCollectionComplete(_ collectionID: String) -> Bool {
        let items = orderedItems(collectionID: collectionID)
        return !items.isEmpty && items.allSatisfy { isWatched($0.id) }
    }

    func setQueueStatus(itemID: String, status: WatchQueueStatus?) {
        guard let item = data.items.byID(itemID), !isWatched(itemID) else { return }
        mutate(action: status.map { "Pinned \(item.title) to \($0.title)" } ?? "Unpinned \(item.title)") { library in
            guard let index = library.items.firstIndex(where: { $0.id == itemID }) else { return }
            library.items[index].queueStatus = status
            library.items[index].pinnedAt = status == nil ? nil : Date().timeIntervalSince1970
        }
    }

    private func priorityRank(for item: MediaItem) -> Int {
        switch effectiveQueueStatus(item) {
        case .watching: 0
        case .nextUp: 1
        case nil: 2
        }
    }

    func isWatched(_ itemID: String) -> Bool {
        data.watchEvents.contains { $0.itemID == itemID }
    }

    func watchCount(_ itemID: String) -> Int {
        data.watchEvents.filter { $0.itemID == itemID }.count
    }

    func latestWatch(_ itemID: String) -> WatchEvent? {
        data.watchEvents.filter { $0.itemID == itemID }.max { $0.watchedAt < $1.watchedAt }
    }

    var viewingSessions: [ViewingSession] { data.viewingSessions ?? [] }

    func viewingSessions(itemID: String) -> [ViewingSession] {
        viewingSessions.filter { $0.itemID == itemID }.sorted { $0.watchedAt > $1.watchedAt }
    }

    func viewingSessions(collectionID: String) -> [(ViewingSession, MediaItem)] {
        let ids = Set(orderedItems(collectionID: collectionID).map(\.id))
        return viewingSessions
            .filter { ids.contains($0.itemID) }
            .sorted { $0.watchedAt > $1.watchedAt }
            .compactMap { session in data.items.byID(session.itemID).map { (session, $0) } }
    }

    func currentPosition(_ itemID: String) -> Int {
        guard let item = data.items.byID(itemID) else { return 0 }
        let latestCompletion = latestWatch(itemID)?.watchedAt ?? -.infinity
        let minutes = viewingSessions
            .filter { $0.itemID == itemID && $0.watchedAt > latestCompletion }
            .reduce(0) { $0 + $1.minutesWatched }
        return min(item.runtimeMinutes, max(0, minutes))
    }

    func remainingMinutes(_ itemID: String) -> Int {
        guard let item = data.items.byID(itemID) else { return 0 }
        if isWatched(itemID) { return 0 }
        return max(0, item.runtimeMinutes - currentPosition(itemID))
    }

    func cycleRemainingMinutes(_ itemID: String) -> Int {
        guard let item = data.items.byID(itemID) else { return 0 }
        return max(0, item.runtimeMinutes - currentPosition(itemID))
    }

    func remainingMinutes(collectionID: String, orderID: String? = nil) -> Int {
        orderedItems(collectionID: collectionID, orderID: orderID).reduce(0) { total, item in
            total + (isWatched(item.id) ? 0 : max(0, item.runtimeMinutes - currentPosition(item.id)))
        }
    }

    func sessionMinutes(collectionID: String) -> Int {
        let ids = Set(orderedItems(collectionID: collectionID).map(\.id))
        return viewingSessions.filter { ids.contains($0.itemID) }.reduce(0) { $0 + $1.minutesWatched }
    }

    func logViewingSession(itemID: String, minutes: Int, watchedAt: Date = Date(), note: String? = nil, source: String = "Next Up") -> Bool {
        guard let item = data.items.byID(itemID), minutes > 0 else { return false }
        let startPosition = currentPosition(itemID)
        let cleanMinutes = min(max(1, minutes), max(1, item.runtimeMinutes - startPosition))
        let endingPosition = min(item.runtimeMinutes, startPosition + cleanMinutes)
        let completed = endingPosition >= item.runtimeMinutes
        let eventID = completed ? UUID().uuidString : nil
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(action: completed ? "Completed \(item.title) across viewing sessions" : "Logged \(cleanMinutes)m of \(item.title)", source: source) { library in
            if library.viewingSessions == nil { library.viewingSessions = [] }
            library.viewingSessions?.append(ViewingSession(
                id: UUID().uuidString,
                itemID: itemID,
                watchedAt: watchedAt.timeIntervalSince1970,
                minutesWatched: cleanMinutes,
                endingPositionMinutes: endingPosition,
                note: cleanNote?.isEmpty == false ? cleanNote : nil,
                source: source,
                watchEventID: eventID
            ))
            if let eventID {
                library.watchEvents.append(WatchEvent(id: eventID, itemID: itemID, watchedAt: watchedAt.timeIntervalSince1970, source: source))
            }
            if let index = library.items.firstIndex(where: { $0.id == itemID }) {
                library.items[index].queueStatus = completed ? nil : .watching
                library.items[index].pinnedAt = completed ? nil : watchedAt.timeIntervalSince1970
            }
        }
        return completed
    }

    func removeViewingSession(_ sessionID: String) {
        guard let session = viewingSessions.first(where: { $0.id == sessionID }) else { return }
        let title = data.items.byID(session.itemID)?.title ?? "item"
        mutate(action: "Removed viewing session: \(title)") { library in
            if let eventID = session.watchEventID {
                library.watchEvents.removeAll { $0.id == eventID }
                library.ratings.removeAll { $0.watchEventID == eventID }
            }
            library.viewingSessions?.removeAll { $0.id == sessionID }
        }
    }

    func ratingsForLatestWatch(_ itemID: String) -> [RatingEntry] {
        guard let event = latestWatch(itemID) else { return [] }
        return ratings(for: event.id)
    }

    func ratings(for watchEventID: String) -> [RatingEntry] {
        data.ratings.filter { $0.watchEventID == watchEventID }
    }

    func ratingsRevealed(eventID: String) -> Bool {
        let names = Set(ratings(for: eventID).map(\.person))
        return data.profiles.allSatisfy { names.contains($0) }
    }

    func rating(itemID: String, person: String, eventID: String? = nil) -> RatingEntry? {
        let entries = eventID.map(ratings(for:)) ?? ratingsForLatestWatch(itemID)
        return entries.first { $0.person == person }
    }

    func ratingsRevealed(_ itemID: String, eventID: String? = nil) -> Bool {
        let entries = eventID.map(ratings(for:)) ?? ratingsForLatestWatch(itemID)
        let names = Set(entries.map(\.person))
        return data.profiles.allSatisfy { names.contains($0) }
    }

    func progress(collectionID: String, orderID: String? = nil) -> (watched: Int, total: Int, watchedMinutes: Int, totalMinutes: Int) {
        let items = orderedItems(collectionID: collectionID, orderID: orderID)
        let watched = items.filter { isWatched($0.id) }
        return (watched.count, items.count, watched.reduce(0) { $0 + $1.runtimeMinutes }, items.reduce(0) { $0 + $1.runtimeMinutes })
    }

    func watchEvents(collectionID: String) -> [(WatchEvent, MediaItem)] {
        let ids = Set(orderedItems(collectionID: collectionID).map(\.id))
        return data.watchEvents
            .filter { ids.contains($0.itemID) }
            .sorted { $0.watchedAt > $1.watchedAt }
            .compactMap { event in data.items.byID(event.itemID).map { (event, $0) } }
    }

    func logWatch(itemID: String, source: String = "Next Up") {
        guard let item = data.items.byID(itemID) else { return }
        let title = item.title
        let position = currentPosition(itemID)
        let minutes = max(1, item.runtimeMinutes - position)
        let eventID = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        mutate(action: "Logged watch: \(title)", source: source) { library in
            if library.viewingSessions == nil { library.viewingSessions = [] }
            library.viewingSessions?.append(ViewingSession(
                id: UUID().uuidString, itemID: itemID, watchedAt: timestamp,
                minutesWatched: minutes, endingPositionMinutes: item.runtimeMinutes,
                note: nil, source: source, watchEventID: eventID
            ))
            library.watchEvents.append(WatchEvent(id: eventID, itemID: itemID, watchedAt: timestamp, source: source))
            if let index = library.items.firstIndex(where: { $0.id == itemID }) {
                library.items[index].queueStatus = nil
                library.items[index].pinnedAt = nil
            }
        }
    }

    func removeLatestWatch(itemID: String) {
        guard let event = latestWatch(itemID) else { return }
        let title = data.items.byID(itemID)?.title ?? "item"
        mutate(action: "Removed latest watch: \(title)") { library in
            library.watchEvents.removeAll { $0.id == event.id }
            library.ratings.removeAll { $0.watchEventID == event.id }
            library.viewingSessions?.removeAll { $0.watchEventID == event.id }
        }
    }

    func submitRating(itemID: String, person: String, stars: Double, eventID: String? = nil) {
        let event: WatchEvent?
        if let eventID { event = data.watchEvents.first { $0.id == eventID && $0.itemID == itemID } }
        else { event = latestWatch(itemID) }
        guard let event, data.profiles.contains(person) else { return }
        let clean = min(5, max(0.5, (stars * 2).rounded() / 2))
        mutate(action: "\(person) submitted a sealed rating", source: person) { library in
            library.ratings.removeAll { $0.watchEventID == event.id && $0.person == person }
            library.ratings.append(RatingEntry(id: UUID().uuidString, itemID: itemID, watchEventID: event.id, person: person, stars: clean, ratedAt: Date().timeIntervalSince1970))
        }
    }

    func addCollection(name: String, kind: CollectionKind) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        mutate(action: "Added collection: \(clean)") { library in
            let id = slug(clean) + "-" + UUID().uuidString.prefix(6).lowercased()
            library.collections.append(MediaCollection(
                id: id, name: clean, subtitle: kind == .series ? "New series" : "New collection", kind: kind,
                symbol: kind == .series ? "play.rectangle.on.rectangle" : "film.stack", accent: "6C63FF",
                position: (library.collections.map(\.position).max() ?? 0) + 1,
                orders: [WatchOrder(id: "\(id)-default", name: kind == .series ? "Episode Order" : "Custom Order", itemIDs: [])]
            ))
        }
    }

    func completeSetup(firstProfile: String, secondProfile: String, providers: [String], keepStarterLibrary: Bool) {
        let first = firstProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = secondProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !second.isEmpty, first.caseInsensitiveCompare(second) != .orderedSame else { return }
        if keepStarterLibrary {
            mutate(action: "Completed first-run setup") { library in
                library.profiles = [first, second]
                library.subscribedProviders = providers
                library.setupComplete = true
            }
        } else {
            withLock {
                var blank = LibraryData.empty
                blank.setupComplete = true
                blank.profiles = [first, second]
                blank.subscribedProviders = providers
                blank.auditLog = [AuditEntry(id: UUID().uuidString, timestamp: Date().timeIntervalSince1970, source: "Next Up", action: "Created an empty library")]
                writeDisk(blank, makeBackup: true)
                data = blank
                updateModifiedDate()
            }
        }
    }

    func updateProfiles(_ names: [String]) {
        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard clean.count == 2, clean.allSatisfy({ !$0.isEmpty }), clean[0].caseInsensitiveCompare(clean[1]) != .orderedSame else { return }
        let old = data.profiles
        mutate(action: "Updated rating profiles") { library in
            for index in library.ratings.indices {
                if library.ratings[index].person == old.first { library.ratings[index].person = clean[0] }
                else if library.ratings[index].person == old.last { library.ratings[index].person = clean[1] }
            }
            library.profiles = clean
            library.setupComplete = true
        }
    }

    func updateProviders(_ providers: [String]) {
        mutate(action: "Updated streaming services") { library in
            library.subscribedProviders = providers
            library.setupComplete = true
        }
    }

    func refreshArtworkStylesIfNeeded() async {
        let candidates = collections.filter {
            $0.externalSource?.provider == "TVmaze" && ($0.artworkURL == nil || $0.accent == "4BBE84")
        }
        guard !candidates.isEmpty else { return }

        var updates: [String: (artwork: String?, accent: String)] = [:]
        for collection in candidates {
            var artwork = collection.artworkURL
            if artwork == nil, let sourceID = collection.externalSource?.id,
               let url = URL(string: "https://api.tvmaze.com/shows/\(sourceID)"),
               let (raw, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let show = try? JSONDecoder().decode(TVMazeShow.self, from: raw) {
                artwork = show.image?.medium ?? show.image?.original
            }
            let accent: String
            if let artwork {
                accent = await ArtworkPalette.accentHex(from: artwork, fallbackSeed: collection.name)
                    ?? ArtworkPalette.fallbackAccent(for: collection.name)
            } else {
                accent = ArtworkPalette.fallbackAccent(for: collection.name)
            }
            updates[collection.id] = (artwork, accent)
        }

        mutate(action: "Refreshed collection artwork colors", source: "TVmaze") { library in
            for index in library.collections.indices {
                guard let update = updates[library.collections[index].id] else { continue }
                library.collections[index].artworkURL = update.artwork
                library.collections[index].accent = update.accent
            }
        }
    }

    func refreshMovieRatingsIfNeeded() async {
        guard let key = WatchmodeKeychain.load() else { return }
        let candidates = data.items.filter { $0.kind == .movie && $0.publicRating == nil }
        guard !candidates.isEmpty else { return }
        let defaultsKey = "NextUp.lastMovieRatingBackfill"
        let lastAttempt = UserDefaults.standard.double(forKey: defaultsKey)
        guard Date().timeIntervalSince1970 - lastAttempt > 30 * 24 * 60 * 60 else { return }

        do {
            let result = try await WatchmodeService.availability(key: key, collections: [], items: candidates)
            applyWatchmodeAvailability(result)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: defaultsKey)
        } catch {
            // This is quiet background enrichment. Search/import and Watchable still
            // report API errors directly when the user explicitly requests them.
        }
    }

    func addItem(title: String, collectionID: String, kind: MediaKind, runtime: Int, year: Int?, season: Int?, episode: Int?, provider: String?, providerURL: String?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        mutate(action: "Added media: \(clean)") { library in
            guard let collectionIndex = library.collections.firstIndex(where: { $0.id == collectionID }) else { return }
            let id = slug(clean) + "-" + UUID().uuidString.prefix(6).lowercased()
            let links = providerURL.flatMap(URL.init(string:)).map { _ in
                [ProviderLink(id: UUID().uuidString, provider: provider ?? "Other", url: providerURL!)]
            } ?? []
            library.items.append(MediaItem(id: id, title: clean, kind: kind, seriesTitle: library.collections.first { $0.id == collectionID }?.name, season: season, episode: episode, releaseYear: year, airDate: nil, runtimeMinutes: max(1, runtime), providerLinks: links))
            for orderIndex in library.collections[collectionIndex].orders.indices {
                library.collections[collectionIndex].orders[orderIndex].itemIDs.append(id)
            }
        }
    }

    func deleteItem(_ itemID: String) {
        guard let item = data.items.byID(itemID) else { return }
        mutate(action: "Deleted media: \(item.title)") { library in
            let eventIDs = Set(library.watchEvents.filter { $0.itemID == itemID }.map(\.id))
            library.collections.indices.forEach { collectionIndex in
                library.collections[collectionIndex].orders.indices.forEach { orderIndex in
                    library.collections[collectionIndex].orders[orderIndex].itemIDs.removeAll { $0 == itemID }
                }
            }
            library.items.removeAll { $0.id == itemID }
            library.watchEvents.removeAll { $0.itemID == itemID }
            library.ratings.removeAll { $0.itemID == itemID || eventIDs.contains($0.watchEventID) }
            library.viewingSessions?.removeAll { $0.itemID == itemID }
        }
    }

    func deleteCollection(_ collectionID: String) {
        guard let collection = collection(collectionID) else { return }
        mutate(action: "Deleted collection: \(collection.name)") { library in
            let candidateIDs = Set(collection.orders.flatMap(\.itemIDs))
            library.collections.removeAll { $0.id == collectionID }
            let stillReferenced = Set(library.collections.flatMap { $0.orders.flatMap(\.itemIDs) })
            let orphaned = candidateIDs.subtracting(stillReferenced)
            let eventIDs = Set(library.watchEvents.filter { orphaned.contains($0.itemID) }.map(\.id))
            library.items.removeAll { orphaned.contains($0.id) }
            library.watchEvents.removeAll { orphaned.contains($0.itemID) }
            library.ratings.removeAll { orphaned.contains($0.itemID) || eventIDs.contains($0.watchEventID) }
            library.viewingSessions?.removeAll { orphaned.contains($0.itemID) }
        }
    }

    func attachLink(itemID: String, provider: String, url: String) {
        guard URL(string: url) != nil else { return }
        mutate(action: "Attached \(provider) link") { library in
            guard let index = library.items.firstIndex(where: { $0.id == itemID }) else { return }
            library.items[index].providerLinks.removeAll { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }
            library.items[index].providerLinks.append(ProviderLink(id: UUID().uuidString, provider: provider, url: url))
        }
    }

    func removeLink(itemID: String, provider: String) {
        guard let item = data.items.byID(itemID), item.providerLinks.contains(where: { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }) else { return }
        mutate(action: "Removed \(provider) link") { library in
            guard let index = library.items.firstIndex(where: { $0.id == itemID }) else { return }
            library.items[index].providerLinks.removeAll { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }
        }
    }

    func applyWatchmodeAvailability(_ result: WatchmodeSyncResult) {
        guard !result.updates.isEmpty || !result.metadataUpdates.isEmpty else { return }
        mutate(action: "Refreshed live availability for \(result.linkedItemCount) library titles", source: "Watchmode") { library in
            let grouped = Dictionary(grouping: result.updates, by: \.itemID)
            let metadata = Dictionary(uniqueKeysWithValues: result.metadataUpdates.map { ($0.itemID, $0) })
            for index in library.items.indices {
                if let update = metadata[library.items[index].id] {
                    if let artwork = update.artworkURL { library.items[index].artworkURL = artwork }
                    if let runtime = update.runtimeMinutes, runtime > 0 { library.items[index].runtimeMinutes = runtime }
                    if let rating = update.publicRating { library.items[index].publicRating = rating }
                    if let score = update.criticScore { library.items[index].criticScore = score }
                    if let rating = update.contentRating { library.items[index].contentRating = rating }
                }
                let updates = grouped[library.items[index].id] ?? []
                if !updates.isEmpty {
                    let refreshedProviders = Set(updates.map { $0.provider.lowercased() })
                    library.items[index].providerLinks.removeAll { refreshedProviders.contains($0.provider.lowercased()) }
                    library.items[index].providerLinks.append(contentsOf: updates.map { update in
                        ProviderLink(
                            id: UUID().uuidString,
                            provider: update.provider,
                            url: update.url,
                            accessType: update.accessType,
                            price: update.price,
                            format: update.format
                        )
                    })
                }
            }
            for index in library.collections.indices where library.collections[index].artworkURL == nil {
                let itemIDs = library.collections[index].orders.first?.itemIDs ?? []
                if let artwork = itemIDs.compactMap({ id in library.items.first(where: { $0.id == id })?.artworkURL }).first {
                    library.collections[index].artworkURL = artwork
                }
            }
        }
    }

    @discardableResult
    func importWatchmodeMovieSeries(name: String, movies: [WatchmodeMovieImport], accent: String) -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !movies.isEmpty else { return "" }
        var returnedID = ""
        mutate(action: "Imported movie series: \(cleanName) (\(movies.count) films)", source: "Watchmode") { library in
            let collectionIndex: Int
            if let existing = library.collections.firstIndex(where: { $0.kind == .films && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
                collectionIndex = existing
            } else {
                let id = "movie-series-\(slug(cleanName))-\(UUID().uuidString.prefix(6).lowercased())"
                library.collections.append(MediaCollection(
                    id: id, name: cleanName, subtitle: "Movie series · imported from Watchmode", kind: .films,
                    symbol: "film.stack.fill", accent: accent,
                    position: (library.collections.map(\.position).max() ?? 0) + 1,
                    orders: [WatchOrder(id: "\(id)-release", name: "Release Order", itemIDs: [])],
                    artworkURL: movies.compactMap(\.artworkURL).first
                ))
                collectionIndex = library.collections.count - 1
            }
            returnedID = library.collections[collectionIndex].id

            var itemIDs: [String] = []
            for movie in movies.sorted(by: { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }) {
                let preferredID = "watchmode-movie-\(movie.watchmodeID)"
                let itemIndex = library.items.firstIndex { item in
                    item.id == preferredID || (item.kind == .movie
                        && item.title.caseInsensitiveCompare(movie.title) == .orderedSame
                        && (item.releaseYear == nil || movie.year == nil || item.releaseYear == movie.year))
                }
                let itemID: String
                if let itemIndex {
                    itemID = library.items[itemIndex].id
                    library.items[itemIndex].title = movie.title
                    library.items[itemIndex].releaseYear = movie.year
                    library.items[itemIndex].runtimeMinutes = movie.runtimeMinutes
                    library.items[itemIndex].artworkURL = movie.artworkURL
                    library.items[itemIndex].providerLinks = movie.providerLinks
                    library.items[itemIndex].publicRating = movie.publicRating
                    library.items[itemIndex].criticScore = movie.criticScore
                    library.items[itemIndex].contentRating = movie.contentRating
                    if library.items[itemIndex].seriesTitle == nil { library.items[itemIndex].seriesTitle = cleanName }
                } else {
                    itemID = preferredID
                    library.items.append(MediaItem(
                        id: itemID, title: movie.title, kind: .movie, seriesTitle: cleanName,
                        season: nil, episode: nil, releaseYear: movie.year, airDate: nil,
                        runtimeMinutes: movie.runtimeMinutes, providerLinks: movie.providerLinks,
                        artworkURL: movie.artworkURL, publicRating: movie.publicRating,
                        criticScore: movie.criticScore, contentRating: movie.contentRating
                    ))
                }
                itemIDs.append(itemID)
            }
            if library.collections[collectionIndex].orders.isEmpty {
                library.collections[collectionIndex].orders = [WatchOrder(id: "\(returnedID)-release", name: "Release Order", itemIDs: itemIDs)]
            } else {
                library.collections[collectionIndex].orders[0].itemIDs = itemIDs
            }
            library.collections[collectionIndex].name = cleanName
            library.collections[collectionIndex].subtitle = "\(itemIDs.count) films · release order"
            library.collections[collectionIndex].accent = accent
            if library.collections[collectionIndex].artworkURL == nil { library.collections[collectionIndex].artworkURL = movies.compactMap(\.artworkURL).first }
            let groupedIDs = Set(itemIDs)
            library.collections.removeAll { collection in
                guard collection.kind == .queue else { return false }
                let ids = Set(collection.orders.flatMap(\.itemIDs))
                return !ids.isEmpty && ids.isSubset(of: groupedIDs)
            }
        }
        return returnedID
    }

    @discardableResult
    func importWatchmodeMovie(_ movie: WatchmodeMovieImport, accent: String) -> String {
        let itemID = "watchmode-movie-\(movie.watchmodeID)"
        let collectionID = "single-movie-\(itemID)"
        mutate(action: "Imported movie: \(movie.title)", source: "Watchmode") { library in
            let collectionIndex: Int
            if let existing = library.collections.firstIndex(where: { collection in
                collection.kind == .queue && collection.orders.contains { $0.itemIDs.contains(itemID) }
            }) {
                collectionIndex = existing
            } else {
                library.collections.append(MediaCollection(
                    id: collectionID,
                    name: movie.title,
                    subtitle: Self.standaloneMovieSubtitle(year: movie.year),
                    kind: .queue,
                    symbol: "popcorn.fill",
                    accent: accent,
                    position: (library.collections.map(\.position).max() ?? 0) + 1,
                    orders: [WatchOrder(id: "\(collectionID)-order", name: "Movie", itemIDs: [])],
                    artworkURL: movie.artworkURL
                ))
                collectionIndex = library.collections.count - 1
            }

            if let itemIndex = library.items.firstIndex(where: { $0.id == itemID }) {
                library.items[itemIndex].title = movie.title
                library.items[itemIndex].releaseYear = movie.year
                library.items[itemIndex].runtimeMinutes = movie.runtimeMinutes
                library.items[itemIndex].artworkURL = movie.artworkURL
                library.items[itemIndex].providerLinks = movie.providerLinks
                library.items[itemIndex].publicRating = movie.publicRating
                library.items[itemIndex].criticScore = movie.criticScore
                library.items[itemIndex].contentRating = movie.contentRating
            } else {
                library.items.append(MediaItem(
                    id: itemID,
                    title: movie.title,
                    kind: .movie,
                    seriesTitle: nil,
                    season: nil,
                    episode: nil,
                    releaseYear: movie.year,
                    airDate: nil,
                    runtimeMinutes: movie.runtimeMinutes,
                    providerLinks: movie.providerLinks,
                    artworkURL: movie.artworkURL,
                    publicRating: movie.publicRating,
                    criticScore: movie.criticScore,
                    contentRating: movie.contentRating
                ))
            }

            if library.collections[collectionIndex].orders.isEmpty {
                library.collections[collectionIndex].orders = [WatchOrder(id: "\(library.collections[collectionIndex].id)-order", name: "Movie", itemIDs: [itemID])]
            } else if !library.collections[collectionIndex].orders[0].itemIDs.contains(itemID) {
                library.collections[collectionIndex].orders[0].itemIDs.append(itemID)
            }
            library.collections[collectionIndex].name = movie.title
            library.collections[collectionIndex].subtitle = Self.standaloneMovieSubtitle(year: movie.year)
            library.collections[collectionIndex].symbol = "popcorn.fill"
            library.collections[collectionIndex].accent = accent
            if let artwork = movie.artworkURL { library.collections[collectionIndex].artworkURL = artwork }
        }
        return collectionID
    }

    func importTVMazeSeries(show: TVMazeShow, episodes: [TVMazeEpisode]) {
        mutate(action: "Imported or refreshed series: \(show.name)", source: "TVmaze") { library in
            let collectionIndex: Int
            if let existing = library.collections.firstIndex(where: { $0.externalSource?.provider == "TVmaze" && $0.externalSource?.id == String(show.id) }) {
                collectionIndex = existing
            } else if let existing = library.collections.firstIndex(where: { $0.name.caseInsensitiveCompare(show.name) == .orderedSame }) {
                collectionIndex = existing
            } else {
                let collectionID = slug(show.name) + "-" + UUID().uuidString.prefix(6).lowercased()
                library.collections.append(MediaCollection(
                    id: collectionID, name: show.name, subtitle: "Imported from TVmaze", kind: .series,
                    symbol: "play.rectangle.on.rectangle", accent: "4BBE84",
                    position: (library.collections.map(\.position).max() ?? 0) + 1,
                    orders: [WatchOrder(id: "\(collectionID)-episodes", name: "Episode Order", itemIDs: [])]
                ))
                collectionIndex = library.collections.count - 1
            }

            library.collections[collectionIndex].externalSource = ExternalSource(provider: "TVmaze", id: String(show.id), url: show.url, lastSyncedAt: Date().timeIntervalSince1970)
            library.collections[collectionIndex].artworkURL = show.image?.medium
            let seasons = Set(episodes.compactMap(\.season)).count
            library.collections[collectionIndex].subtitle = "\(seasons) season\(seasons == 1 ? "" : "s") · synced from TVmaze"

            var orderIDs = library.collections[collectionIndex].orders.first?.itemIDs ?? []
            for episodeData in episodes {
                guard let season = episodeData.season, let number = episodeData.number else { continue }
                let existingItemID = orderIDs.first { itemID in
                    guard let item = library.items.byID(itemID) else { return false }
                    return item.season == season && item.episode == number && item.kind == .episode
                }
                if let existingItemID, let itemIndex = library.items.firstIndex(where: { $0.id == existingItemID }) {
                    library.items[itemIndex].title = episodeData.name
                    library.items[itemIndex].airDate = episodeData.airdate
                    library.items[itemIndex].releaseYear = episodeData.airdate.flatMap { Int($0.prefix(4)) }
                    if let runtime = episodeData.runtime, runtime > 0 { library.items[itemIndex].runtimeMinutes = runtime }
                } else {
                    let itemID = "tvmaze-episode-\(episodeData.id)"
                    guard !library.items.contains(where: { $0.id == itemID }) else { continue }
                    library.items.append(MediaItem(
                        id: itemID, title: episodeData.name, kind: .episode, seriesTitle: show.name,
                        season: season, episode: number, releaseYear: episodeData.airdate.flatMap { Int($0.prefix(4)) },
                        airDate: episodeData.airdate, runtimeMinutes: max(1, episodeData.runtime ?? 30), providerLinks: []
                    ))
                    orderIDs.append(itemID)
                }
            }
            orderIDs = Array(NSOrderedSet(array: orderIDs)) as? [String] ?? orderIDs
            orderIDs.sort { leftID, rightID in
                guard let left = library.items.byID(leftID), let right = library.items.byID(rightID) else { return leftID < rightID }
                if left.season == nil { return true }
                if right.season == nil { return false }
                if left.season != right.season { return (left.season ?? 0) < (right.season ?? 0) }
                return (left.episode ?? 0) < (right.episode ?? 0)
            }
            if library.collections[collectionIndex].orders.isEmpty {
                library.collections[collectionIndex].orders = [WatchOrder(id: "\(library.collections[collectionIndex].id)-episodes", name: "Episode Order", itemIDs: orderIDs)]
            } else {
                library.collections[collectionIndex].orders[0].itemIDs = orderIDs
            }
        }
    }

    func refreshIfChanged() {
        guard let date = try? dataURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              date > lastModified.addingTimeInterval(0.01),
              let loaded = readDisk(), loaded != data else { return }
        data = loaded
        lastModified = date
    }

    func undoLastChange() {
        guard let backupData = try? Data(contentsOf: backupURL),
              let previous = try? decoder.decode(LibraryData.self, from: backupData) else { return }
        withLock {
            let current = try? Data(contentsOf: dataURL)
            try? backupData.write(to: dataURL, options: .atomic)
            if let current { try? current.write(to: backupURL, options: .atomic) }
        }
        data = previous
        updateModifiedDate()
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.title = "Export Next Up Library"
        panel.nameFieldStringValue = "Next Up Backup \(Date().formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.copyItemReplacing(at: dataURL, to: destination)
    }

    func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Restore a Next Up Library"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url,
              let raw = try? Data(contentsOf: source),
              var imported = try? decoder.decode(LibraryData.self, from: raw) else { return }
        imported.auditLog.append(AuditEntry(id: UUID().uuidString, timestamp: Date().timeIntervalSince1970, source: "Next Up", action: "Restored library from backup"))
        withLock {
            writeDisk(imported, makeBackup: true)
            data = imported
            updateModifiedDate()
        }
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataURL])
    }

    private func mutate(action: String, source: String = "Next Up", change: (inout LibraryData) -> Void) {
        withLock {
            var current = readDisk() ?? data
            change(&current)
            current.auditLog.append(AuditEntry(id: UUID().uuidString, timestamp: Date().timeIntervalSince1970, source: source, action: action))
            if current.auditLog.count > 250 { current.auditLog.removeFirst(current.auditLog.count - 250) }
            writeDisk(current, makeBackup: true)
            data = current
            updateModifiedDate()
        }
    }

    private func migrateIfNeeded() {
        if data.schemaVersion < 2 {
            let starWarsLinks: [String: String] = [
                "sw-new-hope": "9a280e53-fcc0-4e17-a02c-b1f40913eb0b", "sw-empire": "0f5c5223-f4f6-46ef-ba8a-69cb0e17d8d3",
                "sw-return": "4b6e7cda-daa5-4f2d-9b61-35bbe562c69c", "sw-phantom": "e0a9fee4-2959-4077-ad8c-8fab4fd6e4d1",
                "sw-clones": "39cbdf17-1bbe-4de2-b4a4-8e342875c2c6", "sw-sith": "eb1e2c5f-69bf-4240-a61f-7ffc4e0311b3",
                "sw-force": "2854a94d-3702-40bd-97a4-12d55a809188", "sw-rogue": "5ec74210-f970-42b7-a39f-8653c0a9eab8",
                "sw-last-jedi": "4c622e6e-6237-44e7-9aaf-db94de0edc3b", "sw-solo": "791bc772-d930-40c9-83ec-5ef85923573e",
                "sw-rise": "3183e62a-47d7-4df0-9e10-6315a56a3bb7"
            ]
            mutate(action: "Upgraded provider availability data") { library in
                for index in library.items.indices {
                    let item = library.items[index]
                    if let entity = starWarsLinks[item.id] {
                        library.items[index].providerLinks = [ProviderLink(id: UUID().uuidString, provider: "Disney+", url: "https://www.disneyplus.com/browse/entity-\(entity)")]
                    } else if item.seriesTitle == "Star Wars: The Clone Wars" && item.kind == .episode {
                        library.items[index].providerLinks = [ProviderLink(id: UUID().uuidString, provider: "Disney+", url: "https://www.disneyplus.com/browse/entity-314f14b4-b70a-4ec6-b634-2559f0b1f77e")]
                    } else if item.seriesTitle == "The Twilight Saga" {
                        library.items[index].providerLinks = [ProviderLink(id: UUID().uuidString, provider: "Disney+", url: "https://www.disneyplus.com/browse/page-d497dbe6-5819-47a4-a47f-d0b7a6e5d74d")]
                    } else if item.id == "love-and-basketball" {
                        library.items[index].providerLinks = []
                    }
                }
                library.schemaVersion = 2
            }
        }

        if data.schemaVersion < 3 {
            mutate(action: "Repaired The Clone Wars movie link") { library in
                if let index = library.items.firstIndex(where: { $0.id == "clone-wars-film" }) {
                    library.items[index].providerLinks.removeAll { $0.provider.caseInsensitiveCompare("Disney+") == .orderedSame }
                    library.items[index].providerLinks.append(ProviderLink(
                        id: UUID().uuidString,
                        provider: "Disney+",
                        url: "https://www.disneyplus.com/browse/entity-24a03eff-e68a-4743-828d-32ba9ffc0c7f"
                    ))
                }
                library.schemaVersion = 3
            }
        }

        if data.schemaVersion < 4 {
            mutate(action: "Consolidated standalone movies into Movies") { library in
                let queueIndex = library.collections.firstIndex { $0.id == "movie-queue" }
                let moviesIndex = library.collections.firstIndex { $0.id == "movies" }
                if let queueIndex, let moviesIndex, queueIndex != moviesIndex {
                    let queueIDs = library.collections[queueIndex].orders.flatMap(\.itemIDs)
                    if library.collections[moviesIndex].orders.isEmpty {
                        library.collections[moviesIndex].orders = [WatchOrder(id: "movies-added", name: "Added Order", itemIDs: queueIDs)]
                    } else {
                        for id in queueIDs where !library.collections[moviesIndex].orders[0].itemIDs.contains(id) {
                            library.collections[moviesIndex].orders[0].itemIDs.append(id)
                        }
                    }
                    if library.collections[moviesIndex].artworkURL == nil {
                        library.collections[moviesIndex].artworkURL = library.collections[queueIndex].artworkURL
                    }
                    library.collections.remove(at: queueIndex)
                } else if let queueIndex {
                    library.collections[queueIndex].id = "movies"
                    library.collections[queueIndex].name = "Movies"
                    library.collections[queueIndex].symbol = "popcorn.fill"
                    if library.collections[queueIndex].orders.isEmpty {
                        library.collections[queueIndex].orders = [WatchOrder(id: "movies-added", name: "Added Order", itemIDs: [])]
                    } else {
                        library.collections[queueIndex].orders[0].id = "movies-added"
                        library.collections[queueIndex].orders[0].name = "Added Order"
                    }
                }
                if let index = library.collections.firstIndex(where: { $0.id == "movies" }) {
                    let count = library.collections[index].orders.first?.itemIDs.count ?? 0
                    library.collections[index].name = "Movies"
                    library.collections[index].subtitle = "\(count) standalone movie\(count == 1 ? "" : "s")"
                    library.collections[index].symbol = "popcorn.fill"
                }
                library.schemaVersion = 4
            }
        }

        if data.schemaVersion < 5 {
            mutate(action: "Enabled partial viewing sessions") { library in
                if library.viewingSessions == nil { library.viewingSessions = [] }
                library.schemaVersion = 5
            }
        }

        if data.schemaVersion < 6 {
            mutate(action: "Split standalone movies into individual sidebar entries") { library in
                let legacyIDs = Set(["movies", "movie-queue"])
                let legacyCollections = library.collections.filter { legacyIDs.contains($0.id) }
                var seenItemIDs = Set<String>()
                let legacyItemIDs = legacyCollections
                    .flatMap { $0.orders.flatMap(\.itemIDs) }
                    .filter { seenItemIDs.insert($0).inserted }
                let firstPosition = legacyCollections.map(\.position).min() ?? ((library.collections.map(\.position).max() ?? 0) + 1)
                library.collections.removeAll { legacyIDs.contains($0.id) }
                let positionShift = max(0, legacyItemIDs.count - 1)
                for index in library.collections.indices where library.collections[index].position > firstPosition {
                    library.collections[index].position += positionShift
                }

                for (offset, itemID) in legacyItemIDs.enumerated() {
                    guard let item = library.items.first(where: { $0.id == itemID }) else { continue }
                    let collectionID = itemID == "love-and-basketball"
                        ? "single-movie-love-and-basketball"
                        : "single-movie-\(itemID)"
                    guard !library.collections.contains(where: { $0.orders.contains { $0.itemIDs.contains(itemID) } }) else { continue }
                    let oldStyle = legacyCollections.first { $0.orders.contains { $0.itemIDs.contains(itemID) } }
                    library.collections.append(MediaCollection(
                        id: collectionID,
                        name: item.title,
                        subtitle: Self.standaloneMovieSubtitle(year: item.releaseYear),
                        kind: .queue,
                        symbol: "popcorn.fill",
                        accent: oldStyle?.accent ?? ArtworkPalette.fallbackAccent(for: item.title),
                        position: firstPosition + offset,
                        orders: [WatchOrder(id: "\(collectionID)-order", name: "Movie", itemIDs: [itemID])],
                        artworkURL: item.artworkURL ?? oldStyle?.artworkURL
                    ))
                }
                library.schemaVersion = 6
            }
        }

        if data.schemaVersion < 7 {
            mutate(action: "Enabled Moviedex priority and public ratings") { library in
                library.schemaVersion = 7
            }
        }

        if data.schemaVersion < 8 {
            mutate(action: "Protected canonical starter release years") { library in
                let canonicalYears: [String: Int] = [
                    "sw-new-hope": 1977, "sw-empire": 1980, "sw-return": 1983,
                    "sw-phantom": 1999, "sw-clones": 2002, "sw-sith": 2005,
                    "sw-force": 2015, "sw-rogue": 2016, "sw-last-jedi": 2017,
                    "sw-solo": 2018, "sw-rise": 2019,
                    "twilight-1": 2008, "twilight-2": 2009, "twilight-3": 2010,
                    "twilight-4": 2011, "twilight-5": 2012
                ]
                for index in library.items.indices {
                    if let year = canonicalYears[library.items[index].id] {
                        library.items[index].releaseYear = year
                    }
                }
                library.schemaVersion = 8
            }
        }
    }

    private static func standaloneMovieSubtitle(year: Int?) -> String {
        year.map { "Standalone movie · \($0)" } ?? "Standalone movie"
    }

    private func readDisk() -> LibraryData? {
        guard let raw = try? Data(contentsOf: dataURL) else { return nil }
        return try? decoder.decode(LibraryData.self, from: raw)
    }

    private func writeDisk(_ value: LibraryData, makeBackup: Bool) {
        if makeBackup, let existing = try? Data(contentsOf: dataURL) {
            try? existing.write(to: backupURL, options: .atomic)
        }
        guard let encoded = try? encoder.encode(value) else { return }
        try? encoded.write(to: dataURL, options: .atomic)
    }

    private func withLock(_ work: () -> Void) {
        var acquired = false
        for _ in 0..<80 {
            do {
                try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: false)
                acquired = true
                break
            } catch {
                Thread.sleep(forTimeInterval: 0.025)
            }
        }
        defer { if acquired { try? FileManager.default.removeItem(at: lockURL) } }
        work()
    }

    private func updateModifiedDate() {
        lastModified = (try? dataURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder { JSONDecoder() }
}

private extension FileManager {
    func copyItemReplacing(at source: URL, to destination: URL) throws {
        if fileExists(atPath: destination.path) { try removeItem(at: destination) }
        try copyItem(at: source, to: destination)
    }
}

private func slug(_ text: String) -> String {
    let allowed = text.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "-" }
    return String(allowed).split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
}
