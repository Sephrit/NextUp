import Foundation

enum SeedFactory {
    static func make() -> LibraryData {
        var data = LibraryData.empty

        let disneySearch = "https://www.disneyplus.com/search"
        func disney(_ id: String? = nil) -> [ProviderLink] {
            let url = id.map { "https://www.disneyplus.com/browse/entity-\($0)" } ?? disneySearch
            return [ProviderLink(id: UUID().uuidString, provider: id == nil ? "Disney+ Search" : "Disney+", url: url)]
        }
        func disneyPage(_ url: String) -> [ProviderLink] {
            [ProviderLink(id: UUID().uuidString, provider: "Disney+", url: url)]
        }

        let starWars: [(String, String, Int, Int, String?)] = [
            ("sw-new-hope", "A New Hope", 1977, 125, "9a280e53-fcc0-4e17-a02c-b1f40913eb0b"),
            ("sw-empire", "The Empire Strikes Back", 1980, 128, "0f5c5223-f4f6-46ef-ba8a-69cb0e17d8d3"),
            ("sw-return", "Return of the Jedi", 1983, 136, "4b6e7cda-daa5-4f2d-9b61-35bbe562c69c"),
            ("sw-phantom", "The Phantom Menace", 1999, 137, "e0a9fee4-2959-4077-ad8c-8fab4fd6e4d1"),
            ("sw-clones", "Attack of the Clones", 2002, 142, "39cbdf17-1bbe-4de2-b4a4-8e342875c2c6"),
            ("sw-sith", "Revenge of the Sith", 2005, 141, "eb1e2c5f-69bf-4240-a61f-7ffc4e0311b3"),
            ("sw-force", "The Force Awakens", 2015, 141, "2854a94d-3702-40bd-97a4-12d55a809188"),
            ("sw-rogue", "Rogue One", 2016, 136, "5ec74210-f970-42b7-a39f-8653c0a9eab8"),
            ("sw-last-jedi", "The Last Jedi", 2017, 154, "4c622e6e-6237-44e7-9aaf-db94de0edc3b"),
            ("sw-solo", "Solo", 2018, 136, "791bc772-d930-40c9-83ec-5ef85923573e"),
            ("sw-rise", "The Rise of Skywalker", 2019, 143, "3183e62a-47d7-4df0-9e10-6315a56a3bb7")
        ]
        data.items += starWars.map {
            MediaItem(id: $0.0, title: $0.1, kind: .movie, seriesTitle: "Star Wars", season: nil, episode: nil, releaseYear: $0.2, airDate: nil, runtimeMinutes: $0.3, providerLinks: disney($0.4))
        }
        let releaseOrder = starWars.map(\.0)
        let chronologicalOrder = ["sw-phantom", "sw-clones", "sw-sith", "sw-solo", "sw-rogue", "sw-new-hope", "sw-empire", "sw-return", "sw-force", "sw-last-jedi", "sw-rise"]
        data.collections.append(MediaCollection(
            id: "star-wars", name: "Star Wars", subtitle: "11 live-action theatrical films", kind: .films,
            symbol: "sparkles", accent: "6C63FF", position: 1,
            orders: [WatchOrder(id: "star-wars-release", name: "Release Order", itemIDs: releaseOrder), WatchOrder(id: "star-wars-chronological", name: "Chronological", itemIDs: chronologicalOrder)]
        ))

        let cloneFilm = MediaItem(id: "clone-wars-film", title: "Star Wars: The Clone Wars", kind: .movie, seriesTitle: "The Clone Wars", season: nil, episode: nil, releaseYear: 2008, airDate: "2008-08-15", runtimeMinutes: 98, providerLinks: disney("24a03eff-e68a-4743-828d-32ba9ffc0c7f"))
        let cloneEpisodes = cloneWarsEpisodes.map {
            MediaItem(id: $0.id, title: $0.title, kind: .episode, seriesTitle: "Star Wars: The Clone Wars", season: $0.season, episode: $0.episode, releaseYear: year(from: $0.airDate), airDate: $0.airDate, runtimeMinutes: 22, providerLinks: disney("314f14b4-b70a-4ec6-b634-2559f0b1f77e"))
        }
        data.items.append(cloneFilm)
        data.items += cloneEpisodes
        data.collections.append(MediaCollection(
            id: "clone-wars", name: "The Clone Wars", subtitle: "2008 film + 7-season animated series", kind: .series,
            symbol: "shield.lefthalf.filled", accent: "E8792E", position: 2,
            orders: [WatchOrder(id: "clone-wars-release", name: "Release Order", itemIDs: [cloneFilm.id] + cloneEpisodes.map(\.id))],
            externalSource: ExternalSource(provider: "TVmaze", id: "563", url: "https://www.tvmaze.com/shows/563/star-wars-the-clone-wars", lastSyncedAt: Date().timeIntervalSince1970)
        ))

        let rickEpisodes = rickAndMortyEpisodes.map {
            MediaItem(id: $0.id, title: $0.title, kind: .episode, seriesTitle: "Rick and Morty", season: $0.season, episode: $0.episode, releaseYear: year(from: $0.airDate), airDate: $0.airDate, runtimeMinutes: 23, providerLinks: disney("4e0f6374-fc81-4da2-b7a9-f7f8c29e7acc"))
        }
        data.items += rickEpisodes
        data.collections.append(MediaCollection(
            id: "rick-and-morty", name: "Rick and Morty", subtitle: "9 seasons", kind: .series,
            symbol: "atom", accent: "4BBE84", position: 3,
            orders: [WatchOrder(id: "rick-release", name: "Episode Order", itemIDs: rickEpisodes.map(\.id))],
            externalSource: ExternalSource(provider: "TVmaze", id: "216", url: "https://www.tvmaze.com/shows/216/rick-and-morty", lastSyncedAt: Date().timeIntervalSince1970)
        ))

        let twilight: [(String, String, Int, Int)] = [
            ("twilight-1", "Twilight", 2008, 121),
            ("twilight-2", "The Twilight Saga: New Moon", 2009, 130),
            ("twilight-3", "The Twilight Saga: Eclipse", 2010, 124),
            ("twilight-4", "Breaking Dawn – Part 1", 2011, 117),
            ("twilight-5", "Breaking Dawn – Part 2", 2012, 115)
        ]
        let twilightPage = "https://www.disneyplus.com/browse/page-d497dbe6-5819-47a4-a47f-d0b7a6e5d74d"
        data.items += twilight.map { MediaItem(id: $0.0, title: $0.1, kind: .movie, seriesTitle: "The Twilight Saga", season: nil, episode: nil, releaseYear: $0.2, airDate: nil, runtimeMinutes: $0.3, providerLinks: disneyPage(twilightPage)) }
        data.collections.append(MediaCollection(
            id: "twilight", name: "Twilight", subtitle: "The five-film saga", kind: .films,
            symbol: "moon.fill", accent: "58708E", position: 4,
            orders: [WatchOrder(id: "twilight-release", name: "Release Order", itemIDs: twilight.map(\.0))]
        ))

        data.collections.append(MediaCollection(
            id: "big-brother", name: "Big Brother", subtitle: "CBS US · Add a season later", kind: .placeholder,
            symbol: "eye.fill", accent: "3678C9", position: 5,
            orders: [WatchOrder(id: "big-brother-order", name: "Episode Order", itemIDs: [])]
        ))

        let loveBasketball = MediaItem(id: "love-and-basketball", title: "Love & Basketball", kind: .movie, seriesTitle: nil, season: nil, episode: nil, releaseYear: 2000, airDate: nil, runtimeMinutes: 124, providerLinks: disney())
        data.items.append(loveBasketball)
        data.collections.append(MediaCollection(
            id: "single-movie-love-and-basketball", name: "Love & Basketball", subtitle: "Standalone movie · 2000", kind: .queue,
            symbol: "popcorn.fill", accent: "D25C7C", position: 6,
            orders: [WatchOrder(id: "single-movie-love-and-basketball-order", name: "Movie", itemIDs: [loveBasketball.id])]
        ))

        data.auditLog.append(AuditEntry(id: UUID().uuidString, timestamp: Date().timeIntervalSince1970, source: "Next Up", action: "Created starter library"))
        return data
    }

    private static func year(from date: String?) -> Int? {
        guard let date, let first = date.split(separator: "-").first else { return nil }
        return Int(first)
    }
}
