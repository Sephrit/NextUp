import XCTest
@testable import NextUp

/// Opt-in integration coverage for maintainers. Normal `swift test` runs skip it;
/// provide NEXTUP_WATCHMODE_KEY to exercise Watchmode's production API.
final class WatchmodeLiveTests: XCTestCase {
    func testCurrentMovieAvailabilityResponse() async throws {
        guard let key = ProcessInfo.processInfo.environment["NEXTUP_WATCHMODE_KEY"], !key.isEmpty else {
            throw XCTSkip("Set NEXTUP_WATCHMODE_KEY to run the live Watchmode check.")
        }
        let item = MediaItem(
            id: "sw-new-hope",
            title: "A New Hope",
            kind: .movie,
            seriesTitle: "Star Wars",
            season: nil,
            episode: nil,
            releaseYear: 1977,
            airDate: nil,
            runtimeMinutes: 121,
            providerLinks: []
        )
        let collection = MediaCollection(
            id: "live-star-wars",
            name: "Star Wars",
            subtitle: "Live test",
            kind: .films,
            symbol: "film",
            accent: "000000",
            position: 0,
            orders: [WatchOrder(id: "release", name: "Release", itemIDs: [item.id])]
        )

        let result = try await WatchmodeService.availability(key: key, collections: [collection], items: [item])
        XCTAssertEqual(result.checkedTitles, 1)
        XCTAssertGreaterThan(result.matchedTitles, 0)
        XCTAssertTrue(result.updates.contains { $0.itemID == item.id && $0.url.hasPrefix("http") })
        XCTAssertTrue(result.metadataUpdates.contains { $0.itemID == item.id && $0.artworkURL?.hasPrefix("http") == true })
    }

    func testMovieSearchAndImportMetadata() async throws {
        guard let key = ProcessInfo.processInfo.environment["NEXTUP_WATCHMODE_KEY"], !key.isEmpty else {
            throw XCTSkip("Set NEXTUP_WATCHMODE_KEY to run the live Watchmode check.")
        }
        let results = try await WatchmodeService.searchMovies(query: "The Godfather", key: key)
        let match = try XCTUnwrap(results.first { $0.title == "The Godfather" && $0.year == 1972 })
        XCTAssertNotNil(match.artworkURL)

        let movie = try await WatchmodeService.movieDetails(id: match.id, key: key)
        XCTAssertEqual(movie.title, "The Godfather")
        XCTAssertEqual(movie.year, 1972)
        XCTAssertGreaterThan(movie.runtimeMinutes, 150)
        XCTAssertNotNil(movie.artworkURL)
        XCTAssertGreaterThan(movie.publicRating ?? 0, 0)
        XCTAssertGreaterThan(movie.criticScore ?? 0, 0)
        XCTAssertNotNil(movie.contentRating)
    }

    func testPrimeRentalPricingAndFreeProviders() async throws {
        guard let key = ProcessInfo.processInfo.environment["NEXTUP_WATCHMODE_KEY"], !key.isEmpty else {
            throw XCTSkip("Set NEXTUP_WATCHMODE_KEY to run the live Watchmode check.")
        }
        let results = try await WatchmodeService.searchMovies(query: "Oppenheimer", key: key)
        let match = try XCTUnwrap(results.first { $0.title == "Oppenheimer" && $0.year == 2023 })
        let movie = try await WatchmodeService.movieDetails(id: match.id, key: key)
        let rental = try XCTUnwrap(movie.providerLinks.first { $0.provider == "Prime Video" && $0.accessType == "rent" })
        XCTAssertGreaterThan(rental.price ?? 0, 0)
        XCTAssertTrue(rental.url.hasPrefix("http"))
    }
}
