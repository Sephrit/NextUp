import XCTest
@testable import NextUp

@MainActor
final class LibraryStoreTests: XCTestCase {
    private func makeStore() -> LibraryStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NextUpTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryStore(folderURL: folder)
    }

    func testStarterLibraryHasExpectedOrdersAndCounts() {
        let store = makeStore()
        XCTAssertEqual(store.orderedItems(collectionID: "star-wars", orderID: "star-wars-release").count, 11)
        XCTAssertEqual(store.orderedItems(collectionID: "star-wars", orderID: "star-wars-release").first?.title, "A New Hope")
        XCTAssertEqual(store.orderedItems(collectionID: "star-wars", orderID: "star-wars-chronological").first?.title, "The Phantom Menace")
        XCTAssertGreaterThan(store.orderedItems(collectionID: "clone-wars").count, 100)
        XCTAssertGreaterThan(store.orderedItems(collectionID: "rick-and-morty").count, 70)
        XCTAssertEqual(store.collection("single-movie-love-and-basketball")?.name, "Love & Basketball")
        XCTAssertEqual(store.orderedItems(collectionID: "single-movie-love-and-basketball").map(\.id), ["love-and-basketball"])
    }

    func testRatingsStaySealedAndRemainAttachedToEachRewatch() {
        let store = makeStore()
        let itemID = "sw-new-hope"
        store.logWatch(itemID: itemID)
        let firstEvent = try! XCTUnwrap(store.latestWatch(itemID))

        store.submitRating(itemID: itemID, person: "Person 1", stars: 4.5)
        XCTAssertFalse(store.ratingsRevealed(itemID))
        store.submitRating(itemID: itemID, person: "Person 2", stars: 3.5)
        XCTAssertTrue(store.ratingsRevealed(itemID))
        XCTAssertTrue(store.ratingsRevealed(eventID: firstEvent.id))

        store.logWatch(itemID: itemID)
        let secondEvent = try! XCTUnwrap(store.latestWatch(itemID))
        XCTAssertNotEqual(firstEvent.id, secondEvent.id)
        XCTAssertTrue(store.ratings(for: secondEvent.id).isEmpty)
        XCTAssertEqual(store.ratings(for: firstEvent.id).count, 2)

        store.submitRating(itemID: itemID, person: "Person 2", stars: 1, eventID: "missing-event")
        XCTAssertTrue(store.ratings(for: secondEvent.id).isEmpty)
        store.submitRating(itemID: itemID, person: "Person 1", stars: 5, eventID: secondEvent.id)
        XCTAssertFalse(store.ratingsRevealed(itemID, eventID: secondEvent.id))
        XCTAssertTrue(store.ratingsRevealed(itemID, eventID: firstEvent.id))
    }

    func testSeriesImportCreatesAllEpisodesAndRefreshDoesNotDuplicate() {
        let store = makeStore()
        let show = TVMazeShow(id: 999_001, url: "https://example.com/show", name: "Regression Show", status: "Running", premiered: "2024-01-01", summary: "Test", image: nil)
        let first = [
            TVMazeEpisode(id: 9001, name: "Pilot", season: 1, number: 1, airdate: "2024-01-01", runtime: 24),
            TVMazeEpisode(id: 9002, name: "Second", season: 1, number: 2, airdate: "2024-01-08", runtime: 25)
        ]
        store.importTVMazeSeries(show: show, episodes: first)
        let collection = try! XCTUnwrap(store.collections.first { $0.name == show.name })
        XCTAssertEqual(store.orderedItems(collectionID: collection.id).count, 2)

        let refreshed = [
            TVMazeEpisode(id: 9001, name: "Pilot (Updated)", season: 1, number: 1, airdate: "2024-01-01", runtime: 26),
            first[1],
            TVMazeEpisode(id: 9003, name: "Third", season: 1, number: 3, airdate: "2024-01-15", runtime: 27)
        ]
        store.importTVMazeSeries(show: show, episodes: refreshed)
        let items = store.orderedItems(collectionID: collection.id)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.first?.title, "Pilot (Updated)")
        XCTAssertEqual(items.first?.runtimeMinutes, 26)
    }

    func testSubscribedServicesControlWatchableLinks() {
        let store = makeStore()
        let item = try! XCTUnwrap(store.data.items.byID("sw-new-hope"))
        store.updateProviders(["Peacock"])
        XCTAssertFalse(store.isAvailable(item))
        store.updateProviders(["Disney+"])
        XCTAssertTrue(store.isAvailable(try! XCTUnwrap(store.data.items.byID(item.id))))
    }

    func testDeleteCanBeUndoneWithHistoryIntact() {
        let store = makeStore()
        store.logWatch(itemID: "sw-new-hope")
        store.submitRating(itemID: "sw-new-hope", person: "Person 1", stars: 4)
        store.deleteItem("sw-new-hope")
        XCTAssertNil(store.data.items.byID("sw-new-hope"))
        store.undoLastChange()
        XCTAssertNotNil(store.data.items.byID("sw-new-hope"))
        XCTAssertEqual(store.watchCount("sw-new-hope"), 1)
        XCTAssertEqual(store.ratingsForLatestWatch("sw-new-hope").count, 1)
    }

    func testMovieImportCreatesDedicatedCollectionWithPosterAndDoesNotDuplicate() {
        let store = makeStore()
        let movie = WatchmodeMovieImport(
            watchmodeID: 1_394_258,
            title: "The Godfather",
            year: 1972,
            runtimeMinutes: 175,
            artworkURL: "https://image.example/poster.jpg",
            providerLinks: [ProviderLink(id: "link", provider: "Paramount+", url: "https://example.com/watch")],
            publicRating: 9.2,
            criticScore: 97,
            contentRating: "R"
        )

        let collectionID = "single-movie-watchmode-movie-1394258"
        XCTAssertEqual(store.importWatchmodeMovie(movie, accent: "8B4513"), collectionID)
        XCTAssertEqual(store.importWatchmodeMovie(movie, accent: "8B4513"), collectionID)

        let collection = try! XCTUnwrap(store.collection(collectionID))
        XCTAssertEqual(collection.name, "The Godfather")
        XCTAssertEqual(collection.artworkURL, movie.artworkURL)
        XCTAssertEqual(collection.orders.first?.itemIDs, ["watchmode-movie-1394258"])
        XCTAssertEqual(store.collection("single-movie-love-and-basketball")?.name, "Love & Basketball")
        let imported = try! XCTUnwrap(store.data.items.byID("watchmode-movie-1394258"))
        XCTAssertEqual(imported.runtimeMinutes, 175)
        XCTAssertEqual(imported.artworkURL, movie.artworkURL)
        XCTAssertEqual(imported.providerLinks.first?.provider, "Paramount+")
        XCTAssertEqual(imported.publicRating, 9.2)
        XCTAssertEqual(imported.criticScore, 97)
        XCTAssertEqual(imported.contentRating, "R")
    }

    func testLegacyMoviesCollectionSplitsIntoIndividualSidebarEntries() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NextUpMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var legacy = SeedFactory.make()
        legacy.schemaVersion = 5
        legacy.collections.removeAll { $0.id == "single-movie-love-and-basketball" }
        legacy.collections.append(MediaCollection(
            id: "movies", name: "Movies", subtitle: "1 standalone movie", kind: .queue,
            symbol: "popcorn.fill", accent: "D25C7C", position: 6,
            orders: [WatchOrder(id: "movies-added", name: "Added Order", itemIDs: ["love-and-basketball"])]
        ))
        try JSONEncoder().encode(legacy).write(to: folder.appendingPathComponent("library.json"))

        let migrated = LibraryStore(folderURL: folder)
        XCTAssertEqual(migrated.data.schemaVersion, 8)
        XCTAssertNil(migrated.collection("movies"))
        XCTAssertEqual(migrated.collection("single-movie-love-and-basketball")?.name, "Love & Basketball")
        XCTAssertEqual(migrated.orderedItems(collectionID: "single-movie-love-and-basketball").map(\.id), ["love-and-basketball"])
    }

    func testAvailabilityMetadataBackfillsMovieAndCollectionArtwork() {
        let store = makeStore()
        var result = WatchmodeSyncResult()
        result.metadataUpdates = [WatchmodeMediaMetadataUpdate(
            itemID: "sw-new-hope",
            artworkURL: "https://image.example/new-hope.jpg",
            runtimeMinutes: 121,
            publicRating: 8.6,
            criticScore: 93,
            contentRating: "PG"
        )]
        store.applyWatchmodeAvailability(result)

        XCTAssertEqual(store.data.items.byID("sw-new-hope")?.artworkURL, "https://image.example/new-hope.jpg")
        XCTAssertEqual(store.data.items.byID("sw-new-hope")?.runtimeMinutes, 121)
        XCTAssertEqual(store.data.items.byID("sw-new-hope")?.publicRating, 8.6)
        XCTAssertEqual(store.data.items.byID("sw-new-hope")?.criticScore, 93)
        XCTAssertEqual(store.data.items.byID("sw-new-hope")?.contentRating, "PG")
        XCTAssertEqual(store.collection("star-wars")?.artworkURL, "https://image.example/new-hope.jpg")
    }

    func testAvailabilityKeepsSubscriptionRentalAndPurchaseOptionsWithPrices() {
        let store = makeStore()
        var result = WatchmodeSyncResult()
        result.updates = [
            WatchmodeAvailabilityUpdate(itemID: "love-and-basketball", provider: "Prime Video", url: "https://example.com/sub", accessType: "sub", price: nil, format: "HD"),
            WatchmodeAvailabilityUpdate(itemID: "love-and-basketball", provider: "Prime Video", url: "https://example.com/rent", accessType: "rent", price: 3.99, format: "4K"),
            WatchmodeAvailabilityUpdate(itemID: "love-and-basketball", provider: "Prime Video", url: "https://example.com/buy", accessType: "buy", price: 12.99, format: "4K")
        ]
        store.applyWatchmodeAvailability(result)
        store.updateProviders(["Prime Video"])

        let links = store.availableLinks(for: try! XCTUnwrap(store.data.items.byID("love-and-basketball")))
        XCTAssertEqual(links.map(\.accessType), ["sub", "rent", "buy"])
        XCTAssertEqual(links[1].price, 3.99)
        XCTAssertEqual(links[1].actionLabel, "Rent $3.99 on Prime Video")
    }

    func testMovieSeriesImportGroupsFilmsWithoutDuplicatingItems() {
        let store = makeStore()
        let movies = [
            WatchmodeMovieImport(watchmodeID: 100, title: "Example Two", year: 2002, runtimeMinutes: 110, artworkURL: "https://example.com/two.jpg", providerLinks: []),
            WatchmodeMovieImport(watchmodeID: 99, title: "Example One", year: 2000, runtimeMinutes: 100, artworkURL: "https://example.com/one.jpg", providerLinks: [])
        ]
        let standaloneID = store.importWatchmodeMovie(movies[1], accent: "123456")
        let id = store.importWatchmodeMovieSeries(name: "Example Saga", movies: movies, accent: "123456")
        store.importWatchmodeMovieSeries(name: "Example Saga", movies: movies, accent: "123456")

        XCTAssertEqual(store.collection(id)?.kind, .films)
        XCTAssertEqual(store.collection(id)?.name, "Example Saga")
        XCTAssertEqual(store.orderedItems(collectionID: id).map(\.title), ["Example One", "Example Two"])
        XCTAssertEqual(store.data.items.filter { $0.id == "watchmode-movie-99" }.count, 1)
        XCTAssertNil(store.collection(standaloneID))
    }

    func testPartialSessionsTrackPositionRemainingAndCompleteOnlyAtRuntime() {
        let store = makeStore()
        let itemID = "sw-new-hope"
        XCTAssertFalse(store.logViewingSession(itemID: itemID, minutes: 40, note: "Stopped for dinner"))
        XCTAssertEqual(store.currentPosition(itemID), 40)
        XCTAssertEqual(store.cycleRemainingMinutes(itemID), 85)
        XCTAssertFalse(store.isWatched(itemID))
        XCTAssertEqual(store.effectiveQueueStatus(try! XCTUnwrap(store.data.items.byID(itemID))), .watching)

        XCTAssertFalse(store.logViewingSession(itemID: itemID, minutes: 60))
        XCTAssertEqual(store.currentPosition(itemID), 100)
        XCTAssertEqual(store.viewingSessions(itemID: itemID).count, 2)
        XCTAssertFalse(store.isWatched(itemID))

        XCTAssertTrue(store.logViewingSession(itemID: itemID, minutes: 25))
        XCTAssertTrue(store.isWatched(itemID))
        XCTAssertEqual(store.watchCount(itemID), 1)
        XCTAssertEqual(store.currentPosition(itemID), 0)
        XCTAssertEqual(store.remainingMinutes(itemID), 0)
        XCTAssertEqual(store.viewingSessions(itemID: itemID).count, 3)
        XCTAssertNotNil(store.viewingSessions(itemID: itemID).first?.watchEventID)
        XCTAssertNil(store.effectiveQueueStatus(try! XCTUnwrap(store.data.items.byID(itemID))))
    }

    func testPinsPrioritizeTitlesAndCompletionMovesCollectionToWatched() {
        let store = makeStore()
        XCTAssertEqual(store.nextUnwatched(collectionID: "star-wars", orderID: "star-wars-release")?.id, "sw-new-hope")

        store.setQueueStatus(itemID: "sw-solo", status: .nextUp)
        XCTAssertEqual(store.nextUnwatched(collectionID: "star-wars", orderID: "star-wars-release")?.id, "sw-solo")
        XCTAssertEqual(store.collectionQueueStatus("star-wars"), .nextUp)

        _ = store.logViewingSession(itemID: "sw-rogue", minutes: 20)
        XCTAssertEqual(store.nextUnwatched(collectionID: "star-wars", orderID: "star-wars-release")?.id, "sw-rogue")
        XCTAssertEqual(store.collectionQueueStatus("star-wars"), .watching)

        store.logWatch(itemID: "love-and-basketball")
        XCTAssertTrue(store.isCollectionComplete("single-movie-love-and-basketball"))
    }

    func testDeletingCompletingSessionAlsoRemovesItsWatchEvent() {
        let store = makeStore()
        XCTAssertTrue(store.logViewingSession(itemID: "love-and-basketball", minutes: 200))
        let session = try! XCTUnwrap(store.viewingSessions(itemID: "love-and-basketball").first)
        XCTAssertTrue(store.isWatched("love-and-basketball"))
        store.removeViewingSession(session.id)
        XCTAssertFalse(store.isWatched("love-and-basketball"))
        XCTAssertTrue(store.viewingSessions(itemID: "love-and-basketball").isEmpty)
    }
}
