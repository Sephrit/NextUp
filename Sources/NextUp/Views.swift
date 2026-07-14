import SwiftUI
import Charts
import AppKit

private enum SidebarFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case watching = "Watching"
    case nextUp = "Next Up"
    case unwatched = "Unwatched"
    case watched = "Watched"
    var id: String { rawValue }
}

private enum SidebarSort: String, CaseIterable, Identifiable {
    case pinned = "Pinned / Added"
    case title = "Title"
    case progress = "Progress"
    case rating = "Rating"
    case recent = "Recently Watched"
    var id: String { rawValue }
}

@MainActor private func resizeMainWindow(width: CGFloat, height: CGFloat) {
    guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { return }
    let current = window.frame
    let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? current
    let origin = NSPoint(
        x: min(max(visible.minX, current.minX), max(visible.minX, visible.maxX - width)),
        y: min(max(visible.minY, current.maxY - height), max(visible.minY, visible.maxY - height))
    )
    window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true, animate: true)
}

struct FullView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var collectionID: String
    @Binding var orderID: String
    @Binding var mode: DetailMode
    let onRate: (String) -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    @State private var collectionPendingDeletion: MediaCollection?
    @State private var sidebarFilter: SidebarFilter = .all
    @State private var sidebarSort: SidebarSort = .pinned

    private var selectedCollection: MediaCollection? { mode.isExplore ? nil : store.collection(collectionID) }
    private var shows: [MediaCollection] { sortedCollections { ($0.kind == .series || $0.kind == .placeholder) && !store.isCollectionComplete($0.id) } }
    private var movieSeries: [MediaCollection] { sortedCollections { $0.kind == .films && !store.isCollectionComplete($0.id) } }
    private var singleMovies: [MediaCollection] { sortedCollections { $0.kind == .queue && !store.isCollectionComplete($0.id) } }
    private var watchedCollections: [MediaCollection] { sortedCollections { store.isCollectionComplete($0.id) } }
    private var visibleCollectionCount: Int { shows.count + movieSeries.count + singleMovies.count + watchedCollections.count }

    var body: some View {
        NavigationSplitView {
            List {
                if !shows.isEmpty {
                    Section("SHOWS") {
                        ForEach(shows) { collection in collectionButton(collection) }
                    }
                }
                if !movieSeries.isEmpty {
                    Section("MOVIE SERIES") {
                        ForEach(movieSeries) { collection in collectionButton(collection) }
                    }
                }
                if !singleMovies.isEmpty {
                    Section("SINGLE MOVIES") {
                        ForEach(singleMovies) { collection in collectionButton(collection) }
                    }
                }
                if !watchedCollections.isEmpty {
                    Section("WATCHED") {
                        ForEach(watchedCollections) { collection in collectionButton(collection) }
                    }
                }
                if visibleCollectionCount == 0 {
                    Label("No collections match this filter", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.callout).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("EXPLORE") {
                    ForEach(DetailMode.exploreViews) { destination in
                        Button {
                            mode = destination
                        } label: {
                            ExploreSidebarRow(mode: destination, isSelected: mode == destination)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 235, ideal: 255, max: 315)
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(
                                colors: [Color(hex: selectedCollection?.accent ?? "6C63FF"), .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            Image(systemName: "play.fill").foregroundStyle(.white)
                        }.frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("NEXT UP").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(store.data.profiles.joined(separator: " & ")).font(.headline)
                            Text("Moviedex · \(moviedexPercent)% complete").font(.caption2.bold()).foregroundStyle(.purple)
                        }
                    }
                    HStack(spacing: 7) {
                        Menu {
                            ForEach(SidebarFilter.allCases) { filter in
                                Button { sidebarFilter = filter } label: {
                                    if sidebarFilter == filter { Label(filter.rawValue, systemImage: "checkmark") }
                                    else { Text(filter.rawValue) }
                                }
                            }
                        } label: {
                            Label(sidebarFilter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                                .lineLimit(1).frame(maxWidth: .infinity)
                        }
                        Menu {
                            ForEach(SidebarSort.allCases) { sort in
                                Button { sidebarSort = sort } label: {
                                    if sidebarSort == sort { Label(sort.rawValue, systemImage: "checkmark") }
                                    else { Text(sort.rawValue) }
                                }
                            }
                        } label: {
                            Label(sidebarSort == .pinned ? "Sort" : sidebarSort.rawValue, systemImage: "arrow.up.arrow.down")
                                .lineLimit(1).frame(maxWidth: .infinity)
                        }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } detail: {
            CollectionDetail(collectionID: collectionID, orderID: $orderID, mode: $mode, onRate: onRate)
                .toolbar {
                    ToolbarItem {
                        Button(action: onSettings) { Image(systemName: "gearshape") }.help("Profile settings")
                    }
                    ToolbarItem {
                        Button { resizeMainWindow(width: 470, height: 760) } label: {
                            Label("Compact View", systemImage: "rectangle.portrait")
                        }.help("Switch to the narrow compact view")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onAdd) { Label("Add Series or Movie", systemImage: "plus") }
                            .keyboardShortcut("n", modifiers: .command)
                    }
                }
        }
        .confirmationDialog(
            "Delete \(collectionPendingDeletion?.name ?? "collection")?",
            isPresented: Binding(get: { collectionPendingDeletion != nil }, set: { if !$0 { collectionPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection and Its History", role: .destructive) {
                guard let id = collectionPendingDeletion?.id else { return }
                store.deleteCollection(id)
                collectionID = store.collections.first?.id ?? ""
                collectionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { collectionPendingDeletion = nil }
        } message: {
            Text("Items used only by this collection, their watch history, and ratings will be removed. You can undo from the Library menu.")
        }
    }

    private func sidebarProgress(_ collection: MediaCollection) -> String {
        if collection.kind == .placeholder { return "Coming later" }
        let p = store.progress(collectionID: collection.id)
        if collection.kind == .queue,
           let item = store.orderedItems(collectionID: collection.id).first,
           let rating = item.publicRating {
            return p.watched == p.total ? "Watched · \(String(format: "%.1f", rating))/10" : "\(String(format: "%.1f", rating))/10 · unwatched"
        }
        return p.total == 0 ? "Empty" : "\(p.watched) of \(p.total) watched"
    }

    private var moviedexPercent: Int {
        guard !store.data.items.isEmpty else { return 0 }
        return Int((Double(Set(store.data.watchEvents.map(\.itemID)).count) / Double(store.data.items.count) * 100).rounded())
    }

    private func sortedCollections(where matches: (MediaCollection) -> Bool) -> [MediaCollection] {
        store.collections.filter { matches($0) && matchesSidebarFilter($0) }.sorted { left, right in
            let rank: (MediaCollection) -> Int = { collection in
                switch store.collectionQueueStatus(collection.id) {
                case .watching: 0
                case .nextUp: 1
                case nil: 2
                }
            }
            let leftRank = rank(left), rightRank = rank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            switch sidebarSort {
            case .pinned:
                return left.position < right.position
            case .title:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .progress:
                let leftProgress = store.progress(collectionID: left.id)
                let rightProgress = store.progress(collectionID: right.id)
                let leftValue = leftProgress.total == 0 ? 0 : Double(leftProgress.watched) / Double(leftProgress.total)
                let rightValue = rightProgress.total == 0 ? 0 : Double(rightProgress.watched) / Double(rightProgress.total)
                return leftValue == rightValue ? left.name < right.name : leftValue > rightValue
            case .rating:
                let leftRating = collectionPublicRating(left)
                let rightRating = collectionPublicRating(right)
                return leftRating == rightRating ? left.name < right.name : leftRating > rightRating
            case .recent:
                let leftDate = store.watchEvents(collectionID: left.id).first?.0.watchedAt ?? 0
                let rightDate = store.watchEvents(collectionID: right.id).first?.0.watchedAt ?? 0
                return leftDate == rightDate ? left.name < right.name : leftDate > rightDate
            }
        }
    }

    private func matchesSidebarFilter(_ collection: MediaCollection) -> Bool {
        switch sidebarFilter {
        case .all: true
        case .watching: store.collectionQueueStatus(collection.id) == .watching
        case .nextUp: store.collectionQueueStatus(collection.id) == .nextUp
        case .unwatched: !store.isCollectionComplete(collection.id)
        case .watched: store.isCollectionComplete(collection.id)
        }
    }

    private func collectionPublicRating(_ collection: MediaCollection) -> Double {
        let values = store.orderedItems(collectionID: collection.id).compactMap(\.publicRating)
        return values.isEmpty ? -1 : values.reduce(0, +) / Double(values.count)
    }

    private func collectionButton(_ collection: MediaCollection) -> some View {
        Button {
            withTransaction(Transaction(animation: nil)) {
                collectionID = collection.id
                orderID = collection.orders.first?.id ?? ""
                if mode.isExplore { mode = .overview }
            }
        } label: {
            CollectionSidebarRow(
                collection: collection,
                progress: sidebarProgress(collection),
                status: store.collectionQueueStatus(collection.id),
                isSelected: collectionID == collection.id && !mode.isExplore
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7))
        .listRowBackground(Color.clear)
        .contextMenu {
            if let next = store.nextUnwatched(collectionID: collection.id) {
                Button("Pin \(next.title) to Watching") { store.setQueueStatus(itemID: next.id, status: .watching) }
                Button("Pin \(next.title) to Next Up") { store.setQueueStatus(itemID: next.id, status: .nextUp) }
                Divider()
            }
            Button("Delete Collection", role: .destructive) {
                collectionPendingDeletion = collection
            }
        }
    }
}

struct ExploreSidebarRow: View {
    let mode: DetailMode
    let isSelected: Bool

    private var color: Color { mode == .discover ? .mint : .blue }
    private var symbol: String { mode == .discover ? "sparkles.rectangle.stack" : "play.tv.fill" }
    private var subtitle: String { mode == .discover ? "Find something new" : "On your services" }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(color.opacity(isSelected ? 0.9 : 0.18))
                Image(systemName: symbol).foregroundStyle(isSelected ? .white : color)
            }
            .frame(width: 30, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(mode.rawValue).fontWeight(.semibold)
                Text(subtitle).font(.caption2).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(isSelected ? color.opacity(0.38) : color.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .frame(height: 47)
    }
}

struct CollectionSidebarRow: View {
    let collection: MediaCollection
    let progress: String
    let status: WatchQueueStatus?
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(
                    colors: isSelected
                        ? [Color(hex: collection.accent).opacity(0.72), Color(hex: collection.accent).opacity(0.22)]
                        : [Color(hex: collection.accent).opacity(0.07), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            HStack(spacing: 10) {
                CollectionThumbnail(collection: collection)
                VStack(alignment: .leading, spacing: 1) {
                    Text(collection.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(progress)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let status {
                    Image(systemName: status.symbol)
                        .font(.caption.bold())
                        .foregroundStyle(status == .watching ? .orange : .purple)
                        .help(status.title)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(Color(hex: collection.accent)).frame(width: 3).padding(.vertical, 7)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .frame(height: 66)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CollectionThumbnail: View {
    @EnvironmentObject private var store: LibraryStore
    let collection: MediaCollection

    private var artworkURL: String? {
        collection.artworkURL ?? collection.orders.first?.itemIDs
            .compactMap { store.data.items.byID($0)?.artworkURL }
            .first
    }

    var body: some View {
        Group {
            if let artworkURL, let url = URL(string: artworkURL) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 42, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16), lineWidth: 0.7))
        .shadow(color: Color(hex: collection.accent).opacity(0.35), radius: 4)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: collection.accent), Color(hex: collection.accent).opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: collection.symbol).font(.caption.bold()).foregroundStyle(.white)
        }
    }
}

struct CollectionDetail: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    @Binding var orderID: String
    @Binding var mode: DetailMode
    let onRate: (String) -> Void
    @State private var searchText = ""

    private var collection: MediaCollection? { store.collection(collectionID) }
    private var items: [MediaItem] { store.orderedItems(collectionID: collectionID, orderID: orderID) }
    private var safeOrderID: Binding<String> {
        Binding(
            get: {
                guard let orders = collection?.orders else { return orderID }
                return orders.contains(where: { $0.id == orderID }) ? orderID : (orders.first?.id ?? "")
            },
            set: { orderID = $0 }
        )
    }

    var body: some View {
        ZStack {
            CollectionBackdrop(collection: mode == .discover || mode == .watchable ? nil : collection)
            VStack(spacing: 0) {
                header
                Divider()
                Group {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        switch mode {
                        case .overview: OverviewView(collectionID: collectionID, orderID: orderID, onRate: onRate)
                        case .list: ChecklistView(collectionID: collectionID, orderID: orderID, onRate: onRate)
                        case .rankings: RankingsView(collectionID: collectionID, onRate: onRate)
                        case .log: WatchLogView(collectionID: collectionID, onRate: onRate)
                        case .discover: DiscoverView(onRate: onRate)
                        case .watchable: WatchableView(onRate: onRate)
                        }
                    } else {
                        GlobalSearchView(query: searchText, onRate: onRate)
                    }
                }
            }
        }
        .librarySearchable(enabled: !mode.isExplore, text: $searchText)
        .onChange(of: mode) { _, newMode in if newMode.isExplore { searchText = "" } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode.isExplore {
                detailTitle
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        detailTitle
                        Spacer(minLength: 12)
                        modePicker
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        detailTitle
                        modePicker
                    }
                }
            }
            if mode != .discover && mode != .watchable, let orders = collection?.orders, orders.count > 1 {
                Picker("Viewing order", selection: safeOrderID) {
                    ForEach(orders) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(24)
    }

    private var detailTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode == .discover ? "Discover" : mode == .watchable ? "What's watchable" : (collection?.name ?? "Next Up"))
                .font(.largeTitle.bold())
                .lineLimit(1)
            Text(mode == .discover ? "Find a series and import every season automatically" : mode == .watchable ? "Live availability matching your selected services" : (collection?.subtitle ?? ""))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var modePicker: some View {
        ViewThatFits(in: .horizontal) {
            Picker("View", selection: $mode) {
                ForEach(DetailMode.collectionViews) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 480)
            Menu {
                ForEach(DetailMode.collectionViews) { candidate in
                    Button { mode = candidate } label: {
                        if candidate == mode { Label(candidate.rawValue, systemImage: "checkmark") }
                        else { Text(candidate.rawValue) }
                    }
                }
            } label: {
                Label(mode.rawValue, systemImage: "rectangle.grid.1x2")
            }
            .buttonStyle(.bordered)
        }
    }
}

struct CollectionBackdrop: View {
    let collection: MediaCollection?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(hex: collection?.accent ?? "6C63FF").opacity(0.17),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let artworkURL = collection?.artworkURL, let url = URL(string: artworkURL) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .saturation(1.2)
                            .opacity(0.14)
                    }
                }
                .frame(width: 360, height: 280)
                .clipped()
                .mask(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let orderID: String
    let onRate: (String) -> Void

    private var items: [MediaItem] { store.orderedItems(collectionID: collectionID, orderID: orderID) }
    private var progress: (watched: Int, total: Int, watchedMinutes: Int, totalMinutes: Int) { store.progress(collectionID: collectionID, orderID: orderID) }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("Ready When You Are", systemImage: "plus.rectangle.on.folder", description: Text("This collection is a placeholder. Add a season or movie whenever you're ready."))
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    MoviedexHero()
                    HStack(spacing: 14) {
                        ProgressRing(value: progress.total == 0 ? 0 : Double(progress.watched) / Double(progress.total), center: "\(percent)%", label: "complete")
                            .frame(width: 142, height: 142)
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                StatCard(icon: "checkmark.circle.fill", color: .green, value: "\(progress.watched)/\(progress.total)", label: "Watched")
                                StatCard(icon: "clock.fill", color: .orange, value: duration(store.remainingMinutes(collectionID: collectionID, orderID: orderID)), label: "Remaining")
                            }
                            HStack(spacing: 12) {
                                StatCard(icon: "arrow.clockwise.circle.fill", color: .blue, value: "\(rewatchCount)", label: "Rewatches")
                                StatCard(icon: "pause.circle.fill", color: .orange, value: duration(store.sessionMinutes(collectionID: collectionID)), label: "Session time")
                                StatCard(icon: "star.fill", color: .yellow, value: averageRating, label: "Shared average")
                            }
                        }
                    }
                    if let next = store.nextUnwatched(collectionID: collectionID, orderID: orderID) {
                        NextCard(item: next, onRate: onRate)
                    } else {
                        CompletionCard(collectionID: collectionID)
                    }
                    TonightPlanner(collectionID: collectionID, orderID: orderID, onRate: onRate)
                    if hasSeasons { SeasonProgressChart(collectionID: collectionID, orderID: orderID) }
                    RatingDifferenceChart(collectionID: collectionID, orderID: orderID)
                }
                .padding(24)
            }
        }
    }

    private var percent: Int { progress.total == 0 ? 0 : Int((Double(progress.watched) / Double(progress.total) * 100).rounded()) }
    private var rewatchCount: Int { max(0, store.data.watchEvents.filter { Set(items.map(\.id)).contains($0.itemID) }.count - progress.watched) }
    private var hasSeasons: Bool { items.contains { $0.season != nil } }
    private var averageRating: String {
        let values = items.flatMap { item -> [Double] in store.ratingsRevealed(item.id) ? store.ratingsForLatestWatch(item.id).map(\.stars) : [] }
        return values.isEmpty ? "—" : String(format: "%.1f ★", values.reduce(0, +) / Double(values.count))
    }
}

struct MoviedexHero: View {
    @EnvironmentObject private var store: LibraryStore

    private var watchedIDs: Set<String> { Set(store.data.watchEvents.map(\.itemID)) }
    private var watched: Int { watchedIDs.count }
    private var total: Int { store.data.items.count }
    private var percent: Int { total == 0 ? 0 : Int((Double(watched) / Double(total) * 100).rounded()) }
    private var completedSets: Int { store.collections.filter { store.isCollectionComplete($0.id) }.count }
    private var rewatches: Int { max(0, store.data.watchEvents.count - watched) }
    private var milestones: [Int] { [1, 5, 10, 25, 50, 100, 250, 500, 1_000] }
    private var nextMilestone: Int { milestones.first(where: { $0 > watched }) ?? max(1_000, ((watched / 500) + 1) * 500) }
    private var previousMilestone: Int { milestones.last(where: { $0 <= watched }) ?? 0 }
    private var level: Int { milestones.filter { $0 <= watched }.count + 1 }
    private var levelProgress: Double {
        guard nextMilestone > previousMilestone else { return 1 }
        return min(1, max(0, Double(watched - previousMilestone) / Double(nextMilestone - previousMilestone)))
    }

    private var badges: [(String, String, Bool)] {
        [
            ("Opening Night", "ticket.fill", watched >= 1),
            ("Double Feature", "film.stack.fill", watched >= 2),
            ("Completionist", "trophy.fill", completedSets >= 1),
            ("Rewatcher", "arrow.clockwise.circle.fill", rewatches >= 1),
            ("Marathon", "flame.fill", watched >= 10),
            ("Curator", "sparkles.rectangle.stack.fill", total >= 50)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { titleBlock; Spacer(); completionMedallion }
                VStack(alignment: .leading, spacing: 16) { titleBlock; completionMedallion }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("LEVEL \(level) PROGRESS").font(.caption.bold()).foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text("\(nextMilestone - watched) titles to Level \(level + 1)").font(.caption.bold()).foregroundStyle(.white.opacity(0.82))
                }
                ProgressView(value: levelProgress)
                    .tint(.yellow)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 9)], spacing: 9) {
                ForEach(Array(badges.enumerated()), id: \.offset) { indexed in
                    let badge = indexed.element
                    HStack(spacing: 8) {
                        Image(systemName: badge.1)
                            .foregroundStyle(badge.2 ? .yellow : .white.opacity(0.28))
                        Text(badge.0).font(.caption.bold()).lineLimit(1)
                            .foregroundStyle(badge.2 ? .white : .white.opacity(0.38))
                        Spacer(minLength: 0)
                        Image(systemName: badge.2 ? "checkmark.seal.fill" : "lock.fill")
                            .font(.caption2).foregroundStyle(badge.2 ? .mint : .white.opacity(0.2))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(.white.opacity(badge.2 ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color(hex: "25105A"), Color(hex: "6036B6"), Color(hex: "B53E85").opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .font(.system(size: 90, weight: .thin))
                .foregroundStyle(.white.opacity(0.08))
                .padding(18)
        }
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.16)))
        .shadow(color: .purple.opacity(0.22), radius: 18, y: 9)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("YOUR MOVIEDEX", systemImage: "sparkles.rectangle.stack.fill")
                .font(.caption.bold()).tracking(1.2).foregroundStyle(.yellow)
            Text("Level \(level) · \(watched) titles collected")
                .font(.title.bold()).foregroundStyle(.white)
            Text(completedSets == 0
                 ? "Finish your first complete movie set to unlock Completionist."
                 : "\(completedSets) complete set\(completedSets == 1 ? "" : "s") archived in Watched. Keep filling every blank.")
                .font(.callout).foregroundStyle(.white.opacity(0.74))
        }
    }

    private var completionMedallion: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 8)
                Circle().trim(from: 0, to: total == 0 ? 0 : Double(watched) / Double(total))
                    .stroke(AngularGradient(colors: [.yellow, .mint, .yellow], center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%").font(.headline.bold().monospacedDigit()).foregroundStyle(.white)
            }.frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(watched) / \(total)").font(.title2.bold().monospacedDigit()).foregroundStyle(.white)
                Text("MOVIEDEX FILLED").font(.caption2.bold()).foregroundStyle(.white.opacity(0.66))
            }
        }
    }
}

struct TonightPlanner: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let orderID: String
    let onRate: (String) -> Void
    @State private var finishBy = Date().addingTimeInterval(2.5 * 3600)

    private var availableMinutes: Int { max(0, Int(finishBy.timeIntervalSinceNow / 60)) }
    private var choices: [MediaItem] {
        store.orderedItems(collectionID: collectionID, orderID: orderID)
            .filter { !store.isWatched($0.id) && store.remainingMinutes($0.id) <= availableMinutes }
            .prefix(4).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What fits tonight?").font(.headline)
                    Text("\(duration(availableMinutes)) available from now").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                DatePicker("Finish by", selection: $finishBy, displayedComponents: .hourAndMinute).labelsHidden()
            }
            if choices.isEmpty {
                Text("Nothing unwatched fits before that time. Pick a later finish time or choose a shorter collection.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(choices) { item in
                    HStack {
                        Image(systemName: item.kind == .episode ? "play.rectangle" : "film")
                        VStack(alignment: .leading) { Text(item.title).fontWeight(.medium).lineLimit(1); Text("\(duration(store.remainingMinutes(item.id))) left · ends \(finishTime(store.remainingMinutes(item.id)))").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        ProviderButton(item: item, compact: true)
                    }
                }
            }
        }
        .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct GlobalSearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var discovery = DiscoveryModel()
    @State private var movieResults: [WatchmodeMovieSearchResult] = []
    @State private var searchingMovies = false
    @State private var importingMovieID: Int?
    @State private var statusMessage: String?
    @State private var showingMovieGroup = false
    let query: String
    let onRate: (String) -> Void

    private var results: [MediaItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.data.items.filter { $0.title.localizedCaseInsensitiveContains(needle) || ($0.seriesTitle?.localizedCaseInsensitiveContains(needle) ?? false) }.prefix(100).map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !results.isEmpty {
                    Label("Already in Next Up", systemImage: "checkmark.circle.fill").font(.title3.bold()).foregroundStyle(.green)
                    ForEach(results) { ItemRow(item: $0, onRate: onRate) }
                } else {
                    Label("Not in your saved library — looking for something new", systemImage: "sparkles")
                        .font(.headline).foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 4)
                HStack {
                    Text("Find new movies & shows").font(.title3.bold())
                    Spacer()
                    if movieResults.count >= 2 {
                        Button { showingMovieGroup = true } label: {
                            Label("Build Movie Series", systemImage: "film.stack.fill")
                        }.buttonStyle(.borderedProminent)
                    }
                }
                if discovery.isLoading || searchingMovies { ProgressView("Searching Watchmode and TVmaze…") }
                if let statusMessage { Text(statusMessage).font(.callout).foregroundStyle(statusMessage.contains("failed") ? .red : .secondary) }
                if let error = discovery.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }

                if !movieResults.isEmpty { Text("Movies").font(.headline).padding(.top, 3) }
                ForEach(Array(movieResults.prefix(15))) { movie in
                    CatalogMovieRow(
                        movie: movie,
                        isAdded: store.containsMovie(title: movie.title, year: movie.year, watchmodeID: movie.id),
                        isImporting: importingMovieID == movie.id,
                        importAction: { importMovie(movie) }
                    )
                }

                if !discovery.results.isEmpty { Text("Shows").font(.headline).padding(.top, 3) }
                ForEach(Array(discovery.results.prefix(15))) { show in
                    CatalogShowRow(
                        show: show,
                        isAdded: store.containsSeries(name: show.name, tvMazeID: show.id),
                        isImporting: false,
                        importAction: { importSeries(show) }
                    )
                }

                if !discovery.isLoading && !searchingMovies && results.isEmpty && movieResults.isEmpty && discovery.results.isEmpty {
                    ContentUnavailableView.search(text: query).frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }.padding(24)
        }
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await searchExternal()
        }
        .sheet(isPresented: $showingMovieGroup) {
            MovieGroupImportSheet(query: query, results: movieResults) { collectionID in
                statusMessage = collectionID.isEmpty ? nil : "Movie series added to your library."
            }
        }
    }

    private func searchExternal() async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { movieResults = []; discovery.results = []; return }
        searchingMovies = true
        statusMessage = nil
        await discovery.search(clean)
        guard !Task.isCancelled else { searchingMovies = false; return }
        if let key = WatchmodeKeychain.load() {
            do { movieResults = try await WatchmodeService.searchMovies(query: clean, key: key) }
            catch { statusMessage = "Movie search failed: \(error.localizedDescription)" }
        } else {
            movieResults = []
            statusMessage = "Show results loaded. Add a Watchmode key in Settings to search movies too."
        }
        searchingMovies = false
    }

    private func importMovie(_ movie: WatchmodeMovieSearchResult) {
        guard let key = WatchmodeKeychain.load() else { statusMessage = "Add a Watchmode key in Settings first."; return }
        importingMovieID = movie.id
        Task {
            do {
                let details = try await WatchmodeService.movieDetails(id: movie.id, key: key)
                let accent: String
                if let artwork = details.artworkURL {
                    accent = await ArtworkPalette.accentHex(from: artwork, fallbackSeed: details.title) ?? ArtworkPalette.fallbackAccent(for: details.title)
                } else {
                    accent = ArtworkPalette.fallbackAccent(for: details.title)
                }
                store.importWatchmodeMovie(details, accent: accent)
                statusMessage = "Added \(details.title)."
            } catch { statusMessage = "Movie import failed: \(error.localizedDescription)" }
            importingMovieID = nil
        }
    }

    private func importSeries(_ show: TVMazeShow) {
        Task {
            do {
                let episodes = try await discovery.episodes(for: show)
                store.importTVMazeSeries(show: show, episodes: episodes)
                await store.refreshArtworkStylesIfNeeded()
                statusMessage = "Added \(show.name) with \(episodes.count) episodes."
            } catch { statusMessage = "Series import failed: \(error.localizedDescription)" }
        }
    }
}

struct CatalogMovieRow: View {
    let movie: WatchmodeMovieSearchResult
    let isAdded: Bool
    let isImporting: Bool
    let importAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: movie.artworkURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                placeholder: { Color.secondary.opacity(0.12).overlay(Image(systemName: "film")) }
                .frame(width: 68, height: 96).clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(movie.title).font(.headline)
                Text(movie.year.map(String.init) ?? "Year unavailable").font(.caption).foregroundStyle(.secondary)
                if isAdded { Label("Already added", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green) }
            }
            Spacer()
            Button(isAdded ? "Added" : isImporting ? "Adding…" : "Add Movie", action: importAction)
                .buttonStyle(.bordered).disabled(isAdded || isImporting)
        }
        .padding(11).background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CatalogShowRow: View {
    let show: TVMazeShow
    let isAdded: Bool
    let isImporting: Bool
    let importAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: show.image?.medium.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                placeholder: { Color.secondary.opacity(0.12).overlay(Image(systemName: "tv")) }
                .frame(width: 68, height: 96).clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(show.name).font(.headline)
                Text([show.premiered?.prefix(4).description, show.status].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                Text(show.plainSummary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                if isAdded { Label("Already added", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green) }
            }
            Spacer()
            Button(isAdded ? "Added" : isImporting ? "Adding…" : "Import Series", action: importAction)
                .buttonStyle(.bordered).disabled(isAdded || isImporting)
        }
        .padding(11).background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MovieGroupImportSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let query: String
    let results: [WatchmodeMovieSearchResult]
    let imported: (String) -> Void
    @State private var name: String
    @State private var selectedIDs: Set<Int>
    @State private var isImporting = false
    @State private var statusMessage: String?

    init(query: String, results: [WatchmodeMovieSearchResult], imported: @escaping (String) -> Void) {
        self.query = query
        self.results = results
        self.imported = imported
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        _name = State(initialValue: clean.isEmpty ? "Movie Series" : clean)
        let needle = clean.lowercased()
        let likely = results.prefix(20).filter { $0.title.lowercased().contains(needle) }
        _selectedIDs = State(initialValue: Set((likely.count >= 2 ? likely : Array(results.prefix(10))).map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build a Movie Series").font(.title.bold())
            Text("Next Up recognized several related movie results. Choose the films that belong together; existing watches and ratings stay attached.").foregroundStyle(.secondary)
            TextField("Series name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button("Select All") { selectedIDs = Set(results.prefix(20).map(\.id)) }.buttonStyle(.borderless)
                Button("Clear") { selectedIDs.removeAll() }.buttonStyle(.borderless)
                Spacer()
                Text("\(selectedIDs.count) selected").foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(Array(results.prefix(20))) { movie in
                        Button {
                            if selectedIDs.contains(movie.id) { selectedIDs.remove(movie.id) } else { selectedIDs.insert(movie.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: movie.artworkURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                                    placeholder: { Color.secondary.opacity(0.1) }
                                    .frame(width: 44, height: 62).clipShape(RoundedRectangle(cornerRadius: 6))
                                Image(systemName: selectedIDs.contains(movie.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selectedIDs.contains(movie.id) ? .green : .secondary)
                                VStack(alignment: .leading) {
                                    Text(movie.title).fontWeight(.semibold)
                                    Text(movie.year.map(String.init) ?? "Year unavailable").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.containsMovie(title: movie.title, year: movie.year, watchmodeID: movie.id) {
                                    Text("Already added").font(.caption.bold()).foregroundStyle(.green)
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if isImporting { ProgressView("Importing posters, runtimes, and availability…") }
            if let statusMessage { Text(statusMessage).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Movie Series") { importGroup() }
                    .buttonStyle(.borderedProminent).disabled(isImporting || selectedIDs.count < 2 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 650, height: 720)
    }

    private func importGroup() {
        guard let key = WatchmodeKeychain.load() else { statusMessage = "Add a Watchmode key in Settings first."; return }
        isImporting = true
        Task {
            var movies: [WatchmodeMovieImport] = []
            for result in results where selectedIDs.contains(result.id) {
                do { movies.append(try await WatchmodeService.movieDetails(id: result.id, key: key)) }
                catch { statusMessage = "Couldn't import \(result.title): \(error.localizedDescription)"; isImporting = false; return }
            }
            let firstArtwork = movies.compactMap(\.artworkURL).first
            let accent: String
            if let firstArtwork {
                accent = await ArtworkPalette.accentHex(from: firstArtwork, fallbackSeed: name) ?? ArtworkPalette.fallbackAccent(for: name)
            } else {
                accent = ArtworkPalette.fallbackAccent(for: name)
            }
            let collectionID = store.importWatchmodeMovieSeries(name: name, movies: movies, accent: accent)
            imported(collectionID)
            isImporting = false
            dismiss()
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var discovery = DiscoveryModel()
    @State private var query = ""
    @State private var importingID: Int?
    @State private var movieResults: [WatchmodeMovieSearchResult] = []
    @State private var searchingMovies = false
    @State private var importingMovieID: Int?
    @State private var syncingCollectionID: String?
    @State private var statusMessage: String?
    @State private var showingMovieGroup = false
    @State private var recommendationResults: [WatchmodeMovieSearchResult] = []
    @State private var loadingRecommendations = false
    let onRate: (String) -> Void

    private var continueSuggestions: [(MediaCollection, MediaItem)] {
        store.collections.compactMap { collection in
            store.nextUnwatched(collectionID: collection.id).map { (collection, $0) }
        }.prefix(6).map { $0 }
    }

    private var savedSearchResults: [MediaItem] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        return store.data.items.filter { $0.title.localizedCaseInsensitiveContains(clean) || ($0.seriesTitle?.localizedCaseInsensitiveContains(clean) ?? false) }.prefix(20).map { $0 }
    }

    private var recommendationSeed: MediaItem? {
        store.data.watchEvents.sorted { $0.watchedAt > $1.watchedAt }
            .compactMap { store.data.items.byID($0.itemID) }
            .first { $0.kind == .movie }
    }

    private var syncedCollections: [MediaCollection] {
        store.collections.filter { $0.externalSource?.provider == "TVmaze" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !continueSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Continue watching").font(.title3.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(continueSuggestions, id: \.1.id) { collection, item in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Label(collection.name, systemImage: collection.symbol).font(.caption.bold()).foregroundStyle(Color(hex: collection.accent))
                                        Text(item.title).font(.headline).lineLimit(2)
                                        Text("\(duration(item.runtimeMinutes)) · ends \(finishTime(item.runtimeMinutes))").font(.caption).foregroundStyle(.secondary)
                                        HStack {
                                            ProviderButton(item: item, compact: true)
                                            Button("Done") { store.logWatch(itemID: item.id); onRate(item.id) }.buttonStyle(.borderless)
                                        }
                                    }
                                    .frame(width: 190, height: 112, alignment: .topLeading).padding(14)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Movie suggestions").font(.title3.bold())
                            Text(recommendationSeed.map { "Inspired by \($0.title)" } ?? "Popular movies worth considering")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { loadRecommendations() } label: {
                            Label(recommendationResults.isEmpty ? "Suggest Movies" : "Refresh", systemImage: "wand.and.stars")
                        }.buttonStyle(.bordered).disabled(loadingRecommendations)
                    }
                    if loadingRecommendations { ProgressView("Finding related movies…") }
                    if !recommendationResults.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recommendationResults) { movie in
                                    VStack(alignment: .leading, spacing: 7) {
                                        AsyncImage(url: movie.artworkURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                                            placeholder: { Color.secondary.opacity(0.12).overlay(Image(systemName: "film")) }
                                            .frame(width: 120, height: 170).clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text(movie.title).font(.headline).lineLimit(2).frame(width: 120, alignment: .leading)
                                        Text(movie.year.map(String.init) ?? "").font(.caption).foregroundStyle(.secondary)
                                        Button(store.containsMovie(title: movie.title, year: movie.year, watchmodeID: movie.id) ? "Added" : "Add") { importMovie(movie) }
                                            .buttonStyle(.bordered).disabled(store.containsMovie(title: movie.title, year: movie.year, watchmodeID: movie.id))
                                    }.frame(width: 130, alignment: .topLeading)
                                }
                            }
                        }
                    }
                }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Find new movies & shows").font(.title3.bold())
                    HStack {
                        TextField("Search outside your library, such as Severance or The Godfather", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { searchNew() }
                        Button("Search") { searchNew() }
                            .buttonStyle(.borderedProminent)
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || discovery.isLoading || searchingMovies)
                    }
                    if discovery.isLoading || searchingMovies { ProgressView("Searching Watchmode and TVmaze…") }
                    if let error = discovery.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                    if let statusMessage { Text(statusMessage).foregroundStyle(statusMessage.contains("failed") ? .red : .green).font(.callout) }

                    if !savedSearchResults.isEmpty {
                        Label("Already in Next Up", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                        ForEach(savedSearchResults) { ItemRow(item: $0, onRate: onRate) }
                    }

                    if !movieResults.isEmpty {
                        HStack {
                            Text("Movies").font(.headline)
                            Spacer()
                            if movieResults.count >= 2 {
                                Button { showingMovieGroup = true } label: { Label("Build Movie Series", systemImage: "film.stack.fill") }
                                    .buttonStyle(.borderedProminent)
                            }
                        }.padding(.top, 4)
                        ForEach(Array(movieResults.prefix(12))) { movie in
                            CatalogMovieRow(movie: movie, isAdded: store.containsMovie(title: movie.title, year: movie.year, watchmodeID: movie.id), isImporting: importingMovieID == movie.id, importAction: { importMovie(movie) })
                        }
                    }

                    if !discovery.results.isEmpty { Text("Shows").font(.headline).padding(.top, 4) }
                    ForEach(Array(discovery.results.prefix(12))) { show in
                        CatalogShowRow(show: show, isAdded: store.containsSeries(name: show.name, tvMazeID: show.id), isImporting: importingID == show.id, importAction: { importSeries(show) })
                    }
                }

                if !syncedCollections.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Check tracked series for new episodes").font(.title3.bold())
                        ForEach(syncedCollections) { collection in
                            HStack {
                                Label(collection.name, systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if let synced = collection.externalSource?.lastSyncedAt {
                                    Text("Last checked \(Date(timeIntervalSince1970: synced).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                                }
                                Button(syncingCollectionID == collection.id ? "Checking…" : "Check Now") { sync(collection) }
                                    .disabled(syncingCollectionID != nil)
                            }.padding(11).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }

                HStack {
                    Text("Series metadata provided by")
                    Link("TVmaze", destination: URL(string: "https://www.tvmaze.com/api")!)
                    Text("under CC BY-SA.")
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .sheet(isPresented: $showingMovieGroup) {
            MovieGroupImportSheet(query: query, results: movieResults) { _ in statusMessage = "Movie series added to your library." }
        }
    }

    private func searchNew() {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        searchingMovies = true
        statusMessage = nil
        Task {
            await discovery.search(clean)
            if let key = WatchmodeKeychain.load() {
                do { movieResults = try await WatchmodeService.searchMovies(query: clean, key: key) }
                catch { statusMessage = "Movie search failed: \(error.localizedDescription)" }
            } else {
                movieResults = []
                statusMessage = "Show results loaded. Add a Watchmode key in Settings to search movies too."
            }
            searchingMovies = false
        }
    }

    private func loadRecommendations() {
        guard let key = WatchmodeKeychain.load() else { statusMessage = "Add a Watchmode key in Settings to get movie suggestions."; return }
        loadingRecommendations = true
        Task {
            do { recommendationResults = try await WatchmodeService.movieSuggestions(seed: recommendationSeed, key: key) }
            catch { statusMessage = "Suggestions failed: \(error.localizedDescription)" }
            loadingRecommendations = false
        }
    }

    private func importMovie(_ movie: WatchmodeMovieSearchResult) {
        guard let key = WatchmodeKeychain.load() else {
            statusMessage = "Add a Watchmode key in Settings before importing movies."
            return
        }
        importingMovieID = movie.id
        Task {
            do {
                let details = try await WatchmodeService.movieDetails(id: movie.id, key: key)
                let accent: String
                if let artworkURL = details.artworkURL {
                    accent = await ArtworkPalette.accentHex(from: artworkURL, fallbackSeed: details.title)
                        ?? ArtworkPalette.fallbackAccent(for: details.title)
                } else {
                    accent = ArtworkPalette.fallbackAccent(for: details.title)
                }
                store.importWatchmodeMovie(details, accent: accent)
                statusMessage = "Added \(details.title) to Single Movies."
            } catch {
                statusMessage = "Movie import failed: \(error.localizedDescription)"
            }
            importingMovieID = nil
        }
    }

    private func importSeries(_ show: TVMazeShow) {
        importingID = show.id
        Task {
            do {
                let episodes = try await discovery.episodes(for: show)
                store.importTVMazeSeries(show: show, episodes: episodes)
                await store.refreshArtworkStylesIfNeeded()
                statusMessage = "Imported \(show.name) with \(episodes.count) episodes."
            } catch { statusMessage = "Import failed: \(error.localizedDescription)" }
            importingID = nil
        }
    }

    private func sync(_ collection: MediaCollection) {
        guard let source = collection.externalSource else { return }
        syncingCollectionID = collection.id
        Task {
            do {
                let show = try await discovery.show(id: source.id)
                let episodes = try await discovery.episodes(for: show)
                store.importTVMazeSeries(show: show, episodes: episodes)
                await store.refreshArtworkStylesIfNeeded()
                statusMessage = "\(show.name) is up to date."
            } catch { statusMessage = "Sync failed: \(error.localizedDescription)" }
            syncingCollectionID = nil
        }
    }
}

struct WatchableView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var includeWatched = false
    @State private var showAllProviders: Set<String> = []
    @State private var collapsedProviders: Set<String> = []
    @State private var isRefreshing = false
    @State private var refreshStatus: String?
    @AppStorage("watchmodeLastAvailabilitySync") private var lastSync = 0.0
    let onRate: (String) -> Void

    private func items(for provider: String) -> [MediaItem] {
        store.data.items.filter { item in
            item.providerLinks.contains { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }
                && (includeWatched || !store.isWatched(item.id))
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var total: Int {
        Set(store.subscribedProviders.flatMap { provider in items(for: provider).map(\.id) }).count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(total) watchable library title\(total == 1 ? "" : "s")").font(.title3.bold())
                        Text("Current US availability for titles already in Next Up, plus your saved links.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isRefreshing { ProgressView().controlSize(.small) }
                    Button {
                        refreshAvailability()
                    } label: {
                        Label(isRefreshing ? "Checking…" : "Refresh Availability", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing || WatchmodeKeychain.load() == nil)
                    Toggle("Include watched", isOn: $includeWatched).toggleStyle(.switch)
                }

                if let refreshStatus {
                    Label(refreshStatus, systemImage: refreshStatus.hasPrefix("Updated") ? "checkmark.circle.fill" : "info.circle")
                        .font(.callout)
                        .foregroundStyle(refreshStatus.hasPrefix("Updated") ? .green : .secondary)
                } else if WatchmodeKeychain.load() == nil {
                    Label("Add a Watchmode key in Settings to check live availability.", systemImage: "key")
                        .font(.callout).foregroundStyle(.secondary)
                } else if lastSync > 0 {
                    Text("Last checked \(Date(timeIntervalSince1970: lastSync).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                ForEach(store.subscribedProviders, id: \.self) { provider in
                    let providerItems = items(for: provider)
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if collapsedProviders.contains(provider) { collapsedProviders.remove(provider) }
                                else { collapsedProviders.insert(provider) }
                            }
                        } label: {
                            HStack {
                                ServiceLabel(provider: provider)
                                Spacer()
                                Text(providerItems.isEmpty ? "Nothing matched" : "\(providerItems.count) title\(providerItems.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Image(systemName: collapsedProviders.contains(provider) ? "chevron.right" : "chevron.down")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(collapsedProviders.contains(provider) ? "Expand" : "Collapse") \(provider)")

                        if !collapsedProviders.contains(provider), providerItems.isEmpty {
                            Text("No library titles currently matched here. Refresh above or add a link from a title's ••• menu.")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                        } else if !collapsedProviders.contains(provider) {
                            ForEach(Array(providerItems.prefix(showAllProviders.contains(provider) ? providerItems.count : 40))) { item in
                                ItemRow(item: item, onRate: onRate)
                            }
                            if providerItems.count > 40 {
                                Button(showAllProviders.contains(provider) ? "Show first 40" : "Show all \(providerItems.count)") {
                                    if showAllProviders.contains(provider) { showAllProviders.remove(provider) }
                                    else { showAllProviders.insert(provider) }
                                }
                                .buttonStyle(.borderless).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if total == 0 {
                    ContentUnavailableView("No Saved Links Yet", systemImage: "play.tv", description: Text("Add provider links manually or ask a connected harness to research and attach current streaming availability."))
                        .frame(maxWidth: .infinity).padding(.vertical, 50)
                }
            }.padding(24)
        }
        .task {
            guard WatchmodeKeychain.load() != nil,
                  Date().timeIntervalSince1970 - lastSync > 12 * 60 * 60 else { return }
            refreshAvailability()
        }
    }

    private func refreshAvailability() {
        guard !isRefreshing else { return }
        guard let key = WatchmodeKeychain.load() else {
            refreshStatus = "Add your Watchmode key in Settings first."
            return
        }
        isRefreshing = true
        refreshStatus = "Checking your movies and series against Watchmode…"
        let collections = store.collections
        let items = store.data.items
        Task {
            do {
                let result = try await WatchmodeService.availability(key: key, collections: collections, items: items)
                store.applyWatchmodeAvailability(result)
                lastSync = Date().timeIntervalSince1970
                let warning = result.warnings.isEmpty ? "" : " · \(result.warnings.count) unmatched"
                refreshStatus = "Updated \(result.linkedItemCount) items across \(result.matchedTitles) matched titles\(warning)."
            } catch {
                refreshStatus = error.localizedDescription
            }
            isRefreshing = false
        }
    }
}

struct ServiceLabel: View {
    let provider: String
    private var service: StreamingServiceOption? { StreamingServiceOption.catalog.first { $0.id.caseInsensitiveCompare(provider) == .orderedSame } }
    var body: some View {
        Label(provider, systemImage: service?.symbol ?? "play.tv.fill")
            .font(.headline).foregroundStyle(Color(hex: service?.color ?? "6C63FF"))
    }
}

struct NextCard: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    let onRate: (String) -> Void
    @State private var showingSession = false

    var body: some View {
        HStack(spacing: 18) {
            MediaArtwork(item: item, cornerRadius: 16)
                .frame(width: 92, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT UP").font(.caption.bold()).foregroundStyle(.indigo)
                Text(item.title).font(.title2.bold()).lineLimit(2)
                Text(itemMetadata(item)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    PublicRatingBadge(item: item)
                    QueueStatusMenu(item: item)
                }
                if store.currentPosition(item.id) > 0 {
                    Text("Resume at \(duration(store.currentPosition(item.id))) · \(duration(store.remainingMinutes(item.id))) left")
                        .font(.callout.bold()).foregroundStyle(.orange)
                } else {
                    Text("Start now · ends \(finishTime(item.runtimeMinutes))").font(.callout.bold()).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(spacing: 9) {
                ProviderButton(item: item)
                Button { showingSession = true } label: { Label("Log Progress", systemImage: "pause.circle") }
                    .buttonStyle(.bordered)
                Button {
                    store.logWatch(itemID: item.id)
                    onRate(item.id)
                } label: { Label("Mark Watched", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.07)))
        .sheet(isPresented: $showingSession) {
            ViewingSessionSheet(itemID: item.id) { completed in if completed { onRate(item.id) } }
        }
    }
}

struct CompletionCard: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text("Collection complete").font(.title2.bold())
                Text("Every item is in your watch log. Pick one below whenever it's time for a rewatch.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ProgressRing: View {
    let value: Double
    let center: String
    let label: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 13)
            Circle().trim(from: 0, to: value).stroke(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 13, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(center).font(.title.bold().monospacedDigit())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(8)
    }
}

struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 25)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline).lineLimit(1)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SeasonDatum: Identifiable {
    let id: String
    let label: String
    let watched: Int
    let total: Int
}

struct SeasonProgressChart: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let orderID: String

    private var data: [SeasonDatum] {
        let items = store.orderedItems(collectionID: collectionID, orderID: orderID).filter { $0.season != nil }
        return Dictionary(grouping: items, by: { $0.season ?? 0 }).keys.sorted().map { season in
            let group = items.filter { $0.season == season }
            return SeasonDatum(id: "s\(season)", label: "Season \(season)", watched: group.filter { store.isWatched($0.id) }.count, total: group.count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Season progress").font(.headline)
            Chart(data) { value in
                BarMark(x: .value("Total", value.total), y: .value("Season", value.label)).foregroundStyle(Color.secondary.opacity(0.12)).cornerRadius(4)
                BarMark(x: .value("Watched", value.watched), y: .value("Season", value.label)).foregroundStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)).cornerRadius(4)
                    .annotation(position: .trailing) { Text("\(value.watched)/\(value.total)").font(.caption2).foregroundStyle(.secondary) }
            }
            .chartXAxis(.hidden)
            .frame(height: max(160, CGFloat(data.count * 32)))
        }
        .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RatingDifference: Identifiable {
    let id: String
    let title: String
    let difference: Double
}

struct RatingDifferenceChart: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let orderID: String

    private var values: [RatingDifference] {
        store.orderedItems(collectionID: collectionID, orderID: orderID).compactMap { item in
            guard store.ratingsRevealed(item.id),
                  let first = store.data.profiles.first,
                  let second = store.data.profiles.last,
                  let firstRating = store.rating(itemID: item.id, person: first)?.stars,
                  let secondRating = store.rating(itemID: item.id, person: second)?.stars else { return nil }
            return RatingDifference(id: item.id, title: item.title, difference: abs(firstRating - secondRating))
        }.sorted { $0.difference > $1.difference }.prefix(6).map { $0 }
    }

    var body: some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Biggest rating differences").font(.headline)
                Chart(values) { value in
                    BarMark(x: .value("Difference", value.difference), y: .value("Title", value.title)).foregroundStyle(.pink.gradient).cornerRadius(4)
                }
                .chartXScale(domain: 0...5)
                .frame(height: max(130, CGFloat(values.count * 34)))
            }
            .padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct ChecklistView: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let orderID: String
    let onRate: (String) -> Void
    @State private var expandedSeasons: Set<Int> = []

    private var items: [MediaItem] { store.orderedItems(collectionID: collectionID, orderID: orderID) }
    private var seasons: [Int] { Array(Set(items.compactMap(\.season))).sorted() }
    private var activeFilms: [MediaItem] { store.prioritizedUnwatchedItems(collectionID: collectionID, orderID: orderID).filter { $0.season == nil } }
    private var priorityFilms: [MediaItem] { activeFilms.filter { store.effectiveQueueStatus($0) != nil } }
    private var unpinnedFilms: [MediaItem] { activeFilms.filter { store.effectiveQueueStatus($0) == nil } }
    private var watchedFilms: [MediaItem] { items.filter { $0.season == nil && store.isWatched($0.id) } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !priorityFilms.isEmpty {
                    HStack {
                        Label("Watching & Next Up", systemImage: "play.circle.fill").font(.headline)
                        Spacer()
                        Text("Pinned to the top").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(priorityFilms) { item in ItemRow(item: item, onRate: onRate) }
                }
                if !unpinnedFilms.isEmpty {
                    HStack {
                        Label("Unwatched", systemImage: "circle.dashed").font(.headline)
                        Spacer()
                        Text("\(unpinnedFilms.count) remaining").font(.caption.bold()).foregroundStyle(.secondary)
                    }.padding(.top, priorityFilms.isEmpty ? 0 : 8)
                    ForEach(unpinnedFilms) { item in ItemRow(item: item, onRate: onRate) }
                }
                if !watchedFilms.isEmpty {
                    HStack {
                        Label("Watched", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
                        Spacer()
                        Text("\(watchedFilms.count) collected").font(.caption.bold()).foregroundStyle(.secondary)
                    }.padding(.top, activeFilms.isEmpty ? 0 : 8)
                    ForEach(watchedFilms) { item in ItemRow(item: item, onRate: onRate) }
                }
                ForEach(seasons, id: \.self) { season in
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if expandedSeasons.contains(season) { expandedSeasons.remove(season) }
                                else { expandedSeasons.insert(season) }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                SeasonHeader(season: season, items: items.filter { $0.season == season })
                                Image(systemName: expandedSeasons.contains(season) ? "chevron.down" : "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(expandedSeasons.contains(season) ? "Collapse Season \(season)" : "Expand Season \(season)")

                        if expandedSeasons.contains(season) {
                        VStack(spacing: 9) {
                            ForEach(items.filter { $0.season == season }) { item in ItemRow(item: item, onRate: onRate) }
                        }.padding(.top, 10)
                        }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(24)
        }
        .onAppear { revealNextSeason() }
        .onChange(of: collectionID) { _, _ in revealNextSeason(reset: true) }
        .onChange(of: orderID) { _, _ in revealNextSeason(reset: true) }
    }

    private func revealNextSeason(reset: Bool = false) {
        if reset { expandedSeasons.removeAll() }
        if let nextSeason = items.first(where: { !store.isWatched($0.id) })?.season ?? seasons.first {
            expandedSeasons.insert(nextSeason)
        }
    }
}

struct SeasonHeader: View {
    @EnvironmentObject private var store: LibraryStore
    let season: Int
    let items: [MediaItem]
    var body: some View {
        HStack {
            Text("Season \(season)").font(.headline)
            Spacer()
            let watched = items.filter { store.isWatched($0.id) }.count
            Text("\(watched)/\(items.count) · \(items.isEmpty ? 0 : Int(Double(watched) / Double(items.count) * 100))%")
                .font(.caption.bold()).foregroundStyle(.secondary)
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    let onRate: (String) -> Void
    @State private var showingLinks = false
    @State private var showingSession = false
    @State private var confirmingDeletion = false

    var body: some View {
        HStack(spacing: 13) {
            Button {
                if store.isWatched(item.id) { onRate(item.id) }
                else { store.logWatch(itemID: item.id); onRate(item.id) }
            } label: {
                Image(systemName: store.isWatched(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(store.isWatched(item.id) ? .green : .secondary)
            }.buttonStyle(.plain)
            MediaArtwork(item: item, cornerRadius: 8)
                .frame(width: 48, height: 68)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let episode = item.episode { Text("E\(episode)").font(.caption.bold()).foregroundStyle(.secondary) }
                    Text(item.title).font(.headline).lineLimit(1)
                    if store.watchCount(item.id) > 1 { Text("×\(store.watchCount(item.id))").font(.caption.bold()).foregroundStyle(.blue) }
                }
                Text(rowProgressText)
                    .font(.caption).foregroundStyle(store.isWatched(item.id) ? .green : .secondary)
            }
            Spacer()
            QueueStatusMenu(item: item)
            PublicRatingBadge(item: item)
            RatingSummary(itemID: item.id)
            ProviderButton(item: item, compact: true)
            Menu {
                if store.isWatched(item.id) {
                    Button("Rate or View Ratings") { onRate(item.id) }
                    Button("Log Rewatch") { store.logWatch(itemID: item.id); onRate(item.id) }
                    Button("Undo Latest Watch") { store.removeLatestWatch(itemID: item.id) }
                } else {
                    Button("Mark Watched") { store.logWatch(itemID: item.id); onRate(item.id) }
                    Divider()
                    Button("Pin to Watching") { store.setQueueStatus(itemID: item.id, status: .watching) }
                    Button("Pin to Next Up") { store.setQueueStatus(itemID: item.id, status: .nextUp) }
                    if item.queueStatus != nil { Button("Remove Pin") { store.setQueueStatus(itemID: item.id, status: nil) } }
                }
                Divider()
                Button("Log Partial Session…") { showingSession = true }
                Button("Streaming Links…") { showingLinks = true }
                Button("Delete from Library", role: .destructive) { confirmingDeletion = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if store.isWatched(item.id) {
                Button("Rate or View Ratings") { onRate(item.id) }
                Button("Log Rewatch") { store.logWatch(itemID: item.id); onRate(item.id) }
                Button("Undo Latest Watch", role: .destructive) { store.removeLatestWatch(itemID: item.id) }
            } else {
                Button("Mark Watched") { store.logWatch(itemID: item.id); onRate(item.id) }
                Divider()
                Button("Pin to Watching") { store.setQueueStatus(itemID: item.id, status: .watching) }
                Button("Pin to Next Up") { store.setQueueStatus(itemID: item.id, status: .nextUp) }
                if item.queueStatus != nil { Button("Remove Pin") { store.setQueueStatus(itemID: item.id, status: nil) } }
            }
            Divider()
            Button("Log Partial Session…") { showingSession = true }
            Button("Streaming Links…") { showingLinks = true }
            Button("Delete from Library", role: .destructive) { confirmingDeletion = true }
        }
        .sheet(isPresented: $showingLinks) { ProviderLinksSheet(itemID: item.id) }
        .sheet(isPresented: $showingSession) {
            ViewingSessionSheet(itemID: item.id) { completed in if completed { onRate(item.id) } }
        }
        .confirmationDialog("Delete \(item.title)?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete Item and Its History", role: .destructive) { store.deleteItem(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes its watch events and ratings. You can undo from the Library menu.")
        }
    }

    private var rowProgressText: String {
        if store.isWatched(item.id), store.currentPosition(item.id) == 0 { return "\(duration(item.runtimeMinutes)) · Watched" }
        let position = store.currentPosition(item.id)
        if position > 0 { return "\(duration(position)) watched · \(duration(store.cycleRemainingMinutes(item.id))) left" }
        return "\(duration(item.runtimeMinutes)) · ends \(finishTime(item.runtimeMinutes))"
    }
}

struct QueueStatusMenu: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem

    private var status: WatchQueueStatus? { store.effectiveQueueStatus(item) }

    var body: some View {
        if store.isWatched(item.id) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).help("Moved to Watched")
        } else {
            Menu {
                Button { store.setQueueStatus(itemID: item.id, status: .watching) } label: {
                    Label("Watching", systemImage: status == .watching ? "checkmark" : "play.circle.fill")
                }
                Button { store.setQueueStatus(itemID: item.id, status: .nextUp) } label: {
                    Label("Next Up", systemImage: status == .nextUp ? "checkmark" : "pin.fill")
                }
                if item.queueStatus != nil {
                    Divider()
                    Button("Remove Pin") { store.setQueueStatus(itemID: item.id, status: nil) }
                }
            } label: {
                Image(systemName: status?.symbol ?? "pin")
                    .foregroundStyle(status == .watching ? .orange : status == .nextUp ? .purple : .secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(status.map { "Pinned to \($0.title)" } ?? "Pin to Watching or Next Up")
        }
    }
}

struct PublicRatingBadge: View {
    let item: MediaItem

    var body: some View {
        if item.publicRating != nil || item.criticScore != nil {
            HStack(spacing: 7) {
                if let rating = item.publicRating {
                    Label(String(format: "%.1f/10", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                if let score = item.criticScore {
                    Text("\(score)%").foregroundStyle(score >= 70 ? .green : .orange)
                }
            }
            .font(.caption.bold().monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .help("Watchmode audience rating and critic score")
        }
    }
}

struct MediaArtwork: View {
    let item: MediaItem
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let artworkURL = item.artworkURL, let url = URL(string: artworkURL) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: item.kind == .episode ? "play.rectangle.fill" : "film.fill")
                .font(.title2).foregroundStyle(.white)
        }
    }
}

struct RatingSummary: View {
    @EnvironmentObject private var store: LibraryStore
    let itemID: String
    var body: some View {
        let ratings = store.ratingsForLatestWatch(itemID)
        if store.ratingsRevealed(itemID) {
            HStack(spacing: 7) {
                ForEach(store.data.profiles, id: \.self) { person in
                    VStack(spacing: 0) {
                        Text(person).font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.1f★", store.rating(itemID: itemID, person: person)?.stars ?? 0)).font(.caption.bold().monospacedDigit())
                    }
                }
            }
        } else if !ratings.isEmpty {
            Label("Sealed", systemImage: "lock.fill").font(.caption.bold()).foregroundStyle(.secondary)
        }
    }
}

struct EventRatingSummary: View {
    @EnvironmentObject private var store: LibraryStore
    let eventID: String
    var body: some View {
        let ratings = store.ratings(for: eventID)
        if store.ratingsRevealed(eventID: eventID) {
            HStack(spacing: 7) {
                ForEach(store.data.profiles, id: \.self) { person in
                    VStack(spacing: 0) {
                        Text(person).font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.1f★", ratings.first { $0.person == person }?.stars ?? 0)).font(.caption.bold().monospacedDigit())
                    }
                }
            }
        } else if !ratings.isEmpty {
            Label("Sealed", systemImage: "lock.fill").font(.caption.bold()).foregroundStyle(.secondary)
        }
    }
}

struct ProviderButton: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    var compact = false
    private var links: [ProviderLink] { store.availableLinks(for: item) }
    var body: some View {
        Group {
            if links.count > 1 {
                Menu {
                    ForEach(links) { link in
                        Button(link.actionLabel + (link.format.map { " · \($0)" } ?? "")) { openInSafari(item, link: link) }
                    }
                } label: {
                    if compact { Image(systemName: "safari.fill") }
                    else { Label("Watch options", systemImage: "safari.fill") }
                }
                .menuStyle(.borderlessButton)
            } else {
                let link = links.first
                Button { if let link { openInSafari(item, link: link) } } label: {
                    if compact { Image(systemName: "safari.fill") }
                    else { Label(link?.actionLabel ?? "Link needed", systemImage: "safari.fill") }
                }
                .buttonStyle(.bordered)
                .disabled(link == nil)
            }
        }
        .help(links.isEmpty ? "No confirmed link for your services" : "Open streaming, rental, or purchase options in Safari")
    }
}

struct RankingsView: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let onRate: (String) -> Void

    private var ranked: [(MediaItem, Double)] {
        store.orderedItems(collectionID: collectionID).compactMap { item in
            guard store.ratingsRevealed(item.id) else { return nil }
            let values = store.ratingsForLatestWatch(item.id).map(\.stars)
            return values.isEmpty ? nil : (item, values.reduce(0, +) / Double(values.count))
        }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        if ranked.isEmpty {
            ContentUnavailableView("No Revealed Rankings", systemImage: "trophy", description: Text("Ratings appear only after both people have submitted."))
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(ranked.enumerated()), id: \.element.0.id) { index, pair in
                        HStack(spacing: 15) {
                            Text("#\(index + 1)").font(.title2.bold()).foregroundStyle(index < 3 ? .yellow : .secondary).frame(width: 48)
                            VStack(alignment: .leading) { Text(pair.0.title).font(.headline); Text(itemMetadata(pair.0)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            RatingSummary(itemID: pair.0.id)
                            Text(String(format: "%.2f", pair.1)).font(.title2.bold().monospacedDigit()).frame(width: 60)
                        }
                        .contentShape(Rectangle()).onTapGesture { onRate(pair.0.id) }
                        .padding(15).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(24)
            }
        }
    }
}

struct WatchLogView: View {
    @EnvironmentObject private var store: LibraryStore
    let collectionID: String
    let onRate: (String) -> Void
    @State private var ratingTarget: WatchLogRatingTarget?
    var body: some View {
        let events = store.watchEvents(collectionID: collectionID)
        let sessions = store.viewingSessions(collectionID: collectionID)
        Group {
            if events.isEmpty && sessions.isEmpty {
                ContentUnavailableView("No Viewing Sessions Yet", systemImage: "calendar.badge.clock", description: Text("Partial sessions, completed watches, and rewatches will all be kept here."))
            } else {
                List {
                    if !sessions.isEmpty {
                        Section("VIEWING SESSIONS") {
                            ForEach(sessions, id: \.0.id) { session, item in
                                HStack(spacing: 13) {
                                    Image(systemName: session.watchEventID == nil ? "pause.circle.fill" : "checkmark.circle.fill")
                                        .font(.title2).foregroundStyle(session.watchEventID == nil ? .orange : .green)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.headline)
                                        Text("\(duration(session.minutesWatched)) watched · ended at \(duration(session.endingPositionMinutes)) · \(duration(max(0, item.runtimeMinutes - session.endingPositionMinutes))) left")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let note = session.note { Text(note).font(.caption).foregroundStyle(.secondary).italic() }
                                    }
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: session.watchedAt).formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                .contextMenu {
                                    Button("Delete Session", role: .destructive) { store.removeViewingSession(session.id) }
                                }
                            }
                        }
                    }
                    if !events.isEmpty {
                        Section("COMPLETED WATCHES") {
                            ForEach(events, id: \.0.id) { event, item in
                                HStack(spacing: 13) {
                                    Image(systemName: store.watchCount(item.id) > 1 ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill").font(.title2).foregroundStyle(store.watchCount(item.id) > 1 ? .blue : .green)
                                    VStack(alignment: .leading) { Text(item.title).font(.headline); Text(Date(timeIntervalSince1970: event.watchedAt).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    EventRatingSummary(eventID: event.id)
                                    Button("Rate") { ratingTarget = WatchLogRatingTarget(itemID: item.id, eventID: event.id) }.buttonStyle(.borderless)
                                }.padding(.vertical, 7)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $ratingTarget) { target in
            RatingSheet(itemID: target.itemID, eventID: target.eventID)
        }
    }
}

struct WatchLogRatingTarget: Identifiable {
    let id = UUID()
    let itemID: String
    let eventID: String
}

struct ViewingSessionSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    let onSaved: (Bool) -> Void
    @State private var minutes = 30
    @State private var watchedAt = Date()
    @State private var note = ""

    private var item: MediaItem? { store.data.items.byID(itemID) }
    private var position: Int { store.currentPosition(itemID) }
    private var remaining: Int { max(1, store.cycleRemainingMinutes(itemID)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Log Viewing Session").font(.title.bold())
                Text(item?.title ?? "Media item").font(.headline)
                Text(position > 0 ? "Currently at \(duration(position)) of \(duration(item?.runtimeMinutes ?? 0))" : "Runtime · \(duration(item?.runtimeMinutes ?? 0))")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(position), total: Double(max(1, item?.runtimeMinutes ?? 1)))
                .tint(.orange)

            Stepper("Watched this session: \(duration(minutes))", value: $minutes, in: 1...remaining)
            HStack {
                ForEach([15, 30, 60], id: \.self) { amount in
                    Button("\(amount)m") { minutes = min(amount, remaining) }.buttonStyle(.bordered)
                }
                Spacer()
                Button("Finished the rest") { minutes = remaining }.buttonStyle(.bordered)
            }
            DatePicker("When", selection: $watchedAt, in: ...Date())
            TextField("Optional note — stopped when…", text: $note, axis: .vertical)
                .lineLimit(2...4)

            HStack {
                Label("After saving: \(duration(max(0, remaining - minutes))) left", systemImage: remaining == minutes ? "checkmark.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(remaining == minutes ? .green : .orange)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(remaining == minutes ? "Save & Complete" : "Save Session") {
                    let completed = store.logViewingSession(itemID: itemID, minutes: minutes, watchedAt: watchedAt, note: note)
                    dismiss()
                    DispatchQueue.main.async { onSaved(completed) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { minutes = min(30, remaining) }
    }
}

struct CompactView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var collectionID: String
    @Binding var orderID: String
    let onRate: (String) -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    @State private var sessionItemID: String?
    @State private var showingSearch = false

    private var collection: MediaCollection? { store.collection(collectionID) }
    private var items: [MediaItem] { store.orderedItems(collectionID: collectionID, orderID: orderID) }
    private var progress: (watched: Int, total: Int, watchedMinutes: Int, totalMinutes: Int) { store.progress(collectionID: collectionID, orderID: orderID) }
    private var safeOrderID: Binding<String> {
        Binding(
            get: {
                guard let orders = collection?.orders else { return orderID }
                return orders.contains(where: { $0.id == orderID }) ? orderID : (orders.first?.id ?? "")
            },
            set: { orderID = $0 }
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), .indigo.opacity(0.09)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) { Text("NEXT UP").font(.caption.bold()).foregroundStyle(.secondary); Text(store.data.profiles.joined(separator: " & ")).font(.title2.bold()) }
                        Spacer()
                        Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.bordered).help("Search library, movies, and shows")
                        Button { resizeMainWindow(width: 1120, height: 760) } label: { Image(systemName: "rectangle.expand.vertical") }
                            .buttonStyle(.bordered).help("Return to full view")
                        Button(action: onSettings) { Image(systemName: "gearshape") }.buttonStyle(.bordered)
                        Button(action: onAdd) { Image(systemName: "plus") }.buttonStyle(.bordered)
                    }
                    Picker("Collection", selection: $collectionID) {
                        ForEach(store.collections) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    if let orders = collection?.orders, orders.count > 1 {
                        Picker("Order", selection: safeOrderID) { ForEach(orders) { Text($0.name).tag($0.id) } }.pickerStyle(.segmented)
                    }
                    HStack(spacing: 17) {
                        ProgressRing(value: progress.total == 0 ? 0 : Double(progress.watched) / Double(progress.total), center: progress.total == 0 ? "—" : "\(Int(Double(progress.watched) / Double(progress.total) * 100))%", label: "complete")
                            .frame(width: 104, height: 104)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(collection?.name ?? "Collection").font(.headline)
                            Text("\(progress.watched) of \(progress.total) watched")
                            Text("\(duration(store.remainingMinutes(collectionID: collectionID, orderID: orderID))) remaining")
                        }.font(.callout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    if let next = store.nextUnwatched(collectionID: collectionID, orderID: orderID) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("NEXT TO WATCH").font(.caption.bold()).foregroundStyle(.indigo)
                            Text(next.title).font(.title2.bold())
                            Text(itemMetadata(next)).foregroundStyle(.secondary)
                            HStack { PublicRatingBadge(item: next); QueueStatusMenu(item: next) }
                            HStack { Image(systemName: "clock.fill").foregroundStyle(.orange); Text(store.currentPosition(next.id) > 0 ? "Resume · \(duration(store.remainingMinutes(next.id))) left" : "Start now · finish \(finishTime(next.runtimeMinutes))").fontWeight(.semibold) }
                            ProviderButton(item: next)
                                .frame(maxWidth: .infinity)
                            Button { sessionItemID = next.id } label: { Label("Log Progress", systemImage: "pause.circle.fill").frame(maxWidth: .infinity) }
                                .controlSize(.large).buttonStyle(.bordered)
                            Button {
                                store.logWatch(itemID: next.id)
                                onRate(next.id)
                            } label: { Label("Mark Watched", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                                .controlSize(.large).buttonStyle(.borderedProminent).tint(.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    } else if items.isEmpty {
                        ContentUnavailableView("Empty Collection", systemImage: "plus", description: Text("Add something whenever you're ready."))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(.yellow)
                            Text("Collection complete").font(.title2.bold())
                            Text("Everything is safely in your watch log.").foregroundStyle(.secondary)
                        }.padding(24)
                    }
                }.padding(18)
            }
        }
        .sheet(item: Binding(
            get: { sessionItemID.map { IdentifiedString(value: $0) } },
            set: { sessionItemID = $0?.value }
        )) { target in
            ViewingSessionSheet(itemID: target.value) { completed in if completed { onRate(target.value) } }
        }
        .sheet(isPresented: $showingSearch) { CompactSearchSheet(onRate: onRate) }
    }
}

struct CompactSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onRate: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Search").font(.title2.bold())
                TextField("Search library, movies & shows", text: $query).textFieldStyle(.roundedBorder)
                Button("Done") { dismiss() }
            }.padding(18)
            Divider()
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Find Anything", systemImage: "magnifyingglass", description: Text("Saved matches appear first, followed by new movies and shows you can add."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GlobalSearchView(query: query, onRate: onRate)
            }
        }.frame(width: 760, height: 720)
    }
}

struct FirstRunSheet: View {
    @State private var first = ""
    @State private var second = ""
    @State private var keepStarter = true
    @State private var providers: Set<String> = ["Disney+"]
    let complete: (String, String, [String], Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(.indigo.gradient); Image(systemName: "play.fill").font(.title).foregroundStyle(.white) }.frame(width: 58, height: 58)
                VStack(alignment: .leading) { Text("Welcome to Next Up").font(.title.bold()); Text("A private watch tracker for two people").foregroundStyle(.secondary) }
            }
            Text("Who will be watching and rating together?").font(.headline)
            TextField("First person's name", text: $first)
            TextField("Second person's name", text: $second)
            Text("Which streaming services do you have?").font(.headline)
            ServicePicker(selection: $providers)
            Toggle("Start with the sample Star Wars, Clone Wars, Rick and Morty, Twilight, and movie collections", isOn: $keepStarter)
            Text("You can add, rename, or remove media later. Everything stays on this Mac unless you export it.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Start Watching") { complete(first, second, Array(providers).sorted(), keepStarter) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(first.trimmingCharacters(in: .whitespaces).isEmpty || second.trimmingCharacters(in: .whitespaces).isEmpty || first.caseInsensitiveCompare(second) == .orderedSame) }
        }.padding(28).frame(width: 520)
    }
}

struct ProfileSettingsSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""
    @State private var providers: Set<String> = []
    @State private var watchmodeKey = ""
    @State private var hasWatchmodeKey = false
    @State private var watchmodeStatus: String?
    @State private var testingWatchmode = false
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings").font(.title.bold())
                    Text("Rating profiles").font(.headline)
                    Text("Renaming a profile keeps its existing ratings and watch history.").font(.callout).foregroundStyle(.secondary)
                    TextField("First person's name", text: $first)
                    TextField("Second person's name", text: $second)
                    Text("Streaming services").font(.headline)
                    ServicePicker(selection: $providers)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Label(hasWatchmodeKey ? "API key stored securely" : "No API key stored", systemImage: hasWatchmodeKey ? "checkmark.shield.fill" : "key")
                                    .foregroundStyle(hasWatchmodeKey ? .green : .secondary)
                                Spacer()
                                if testingWatchmode { ProgressView().controlSize(.small) }
                            }
                            SecureField(hasWatchmodeKey ? "Paste a replacement key" : "Paste your Watchmode API key", text: $watchmodeKey)
                                .textFieldStyle(.roundedBorder)
                            Text("The key is saved in macOS Keychain—not your library, backups, logs, or GitHub repository.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let watchmodeStatus {
                                Text(watchmodeStatus)
                                    .font(.callout)
                                    .foregroundStyle(watchmodeStatus.hasPrefix("Connected") ? .green : .red)
                            }
                            HStack {
                                Button(hasWatchmodeKey && watchmodeKey.isEmpty ? "Test Saved Key" : "Save & Test") { testWatchmodeKey() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(testingWatchmode || (!hasWatchmodeKey && watchmodeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                                if hasWatchmodeKey {
                                    Button("Remove Key", role: .destructive) { removeWatchmodeKey() }
                                }
                            }
                        }.padding(5)
                    } label: {
                        Label("Live Availability · Watchmode", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Export Backup…") { store.exportLibrary() }
                Button("Restore…") { store.importLibrary() }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    store.updateProfiles([first, second])
                    store.updateProviders(Array(providers).sorted())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(first.trimmingCharacters(in: .whitespaces).isEmpty || second.trimmingCharacters(in: .whitespaces).isEmpty || first.caseInsensitiveCompare(second) == .orderedSame)
            }.padding(18)
        }
        .frame(width: 540, height: 650)
        .onAppear {
            first = store.data.profiles.first ?? ""
            second = store.data.profiles.last ?? ""
            providers = Set(store.subscribedProviders)
            hasWatchmodeKey = WatchmodeKeychain.load() != nil
        }
    }

    private func testWatchmodeKey() {
        guard let candidate = watchmodeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? WatchmodeKeychain.load()
                : watchmodeKey.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            watchmodeStatus = "Enter a Watchmode API key."
            return
        }
        testingWatchmode = true
        watchmodeStatus = nil
        Task {
            do {
                try await WatchmodeService.test(key: candidate)
                try WatchmodeKeychain.save(candidate)
                hasWatchmodeKey = true
                watchmodeKey = ""
                watchmodeStatus = "Connected to Watchmode successfully."
            } catch {
                watchmodeStatus = error.localizedDescription
            }
            testingWatchmode = false
        }
    }

    private func removeWatchmodeKey() {
        do {
            try WatchmodeKeychain.remove()
            hasWatchmodeKey = false
            watchmodeKey = ""
            watchmodeStatus = nil
        } catch {
            watchmodeStatus = error.localizedDescription
        }
    }
}

struct ServicePicker: View {
    @Binding var selection: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(StreamingServiceOption.catalog) { service in
                Button {
                    if selection.contains(service.id) { selection.remove(service.id) } else { selection.insert(service.id) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selection.contains(service.id) ? "checkmark.circle.fill" : service.symbol)
                            .foregroundStyle(selection.contains(service.id) ? Color(hex: service.color) : .secondary)
                        Text(service.name).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection.contains(service.id) ? Color(hex: service.color).opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}

struct RatingSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    var eventID: String? = nil
    @State private var person: String?
    @State private var stars = 3.0
    @State private var justSaved: String?

    private var item: MediaItem? { store.data.items.byID(itemID) }
    private var revealed: Bool { store.ratingsRevealed(itemID, eventID: eventID) }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text(item?.title ?? "Rating").font(.title2.bold()).multilineTextAlignment(.center)
                Text("Ratings stay sealed until both are submitted").font(.callout).foregroundStyle(.secondary)
            }
            if let person {
                VStack(spacing: 13) {
                    Text("\(person)'s rating").font(.headline)
                    StarDisplay(value: stars).font(.largeTitle)
                    Text(String(format: "%.1f out of 5", stars)).font(.title3.bold().monospacedDigit())
                    Slider(value: $stars, in: 0.5...5, step: 0.5).frame(width: 280)
                    Button("Seal \(person)'s Rating") {
                        store.submitRating(itemID: itemID, person: person, stars: stars, eventID: eventID)
                        justSaved = person
                        self.person = nil
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Back") { self.person = nil }.buttonStyle(.plain)
                }
            } else if revealed {
                revealedView
            } else if let saved = justSaved {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.indigo)
                Text("\(saved)'s rating is sealed").font(.headline)
                Text("Pass the Mac to \(otherPerson(saved)). The score won't appear until they submit theirs.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Continue as \(otherPerson(saved))") { person = otherPerson(saved); justSaved = nil; loadExisting() }.buttonStyle(.borderedProminent)
            } else {
                Text("Who's rating?").font(.headline)
                HStack(spacing: 14) {
                    ForEach(store.data.profiles, id: \.self) { name in
                        Button {
                            person = name
                            stars = store.rating(itemID: itemID, person: name, eventID: eventID)?.stars ?? 3
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: store.rating(itemID: itemID, person: name, eventID: eventID) == nil ? "person.crop.circle" : "lock.circle.fill").font(.largeTitle)
                                Text(name).font(.headline)
                                Text(store.rating(itemID: itemID, person: name, eventID: eventID) == nil ? "Not submitted" : "Rating sealed").font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 140, height: 105)
                        }.buttonStyle(.bordered)
                    }
                }
            }
            HStack { Spacer(); Button(revealed ? "Done" : "Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(26).frame(width: 430).frame(minHeight: 370)
    }

    private var revealedView: some View {
        VStack(spacing: 14) {
            Text("Ratings revealed!").font(.title3.bold())
            HStack(spacing: 18) {
                ForEach(store.data.profiles, id: \.self) { name in
                    VStack(spacing: 7) {
                        Text(name).font(.headline)
                        StarDisplay(value: store.rating(itemID: itemID, person: name, eventID: eventID)?.stars ?? 0)
                        Text(String(format: "%.1f", store.rating(itemID: itemID, person: name, eventID: eventID)?.stars ?? 0)).font(.title.bold().monospacedDigit())
                        Button("Update") { person = name; stars = store.rating(itemID: itemID, person: name, eventID: eventID)?.stars ?? 3 }.buttonStyle(.borderless)
                    }.frame(width: 150).padding(14).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func otherPerson(_ name: String) -> String { store.data.profiles.first { $0 != name } ?? "the other person" }
    private func loadExisting() { if let person { stars = store.rating(itemID: itemID, person: person, eventID: eventID)?.stars ?? 3 } }
}

struct StarDisplay: View {
    let value: Double
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                let amount = value - Double(index - 1)
                Image(systemName: amount >= 1 ? "star.fill" : amount >= 0.5 ? "star.leadinghalf.filled" : "star")
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct ProviderLinksSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var provider = "Disney+"
    @State private var url = ""

    private var item: MediaItem? { store.data.items.byID(itemID) }
    private var validURL: Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Streaming Links").font(.title.bold())
                Text(item?.title ?? "Media item").font(.headline)
                Text("Add a direct provider page so Watch opens it in Safari. Availability is shown only for services selected in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let links = item?.providerLinks, !links.isEmpty {
                VStack(spacing: 8) {
                    ForEach(links) { link in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(link.actionLabel, systemImage: "safari.fill")
                                if let format = link.format { Text(format).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(link.url).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Spacer()
                            Button("Open") { if let item { openInSafari(item, link: link) } }.buttonStyle(.borderless)
                            Button(role: .destructive) { store.removeLink(itemID: itemID, provider: link.provider) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        .padding(10).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                ContentUnavailableView("No Streaming Links", systemImage: "link.badge.plus", description: Text("Paste a direct title or series URL below."))
                    .frame(maxHeight: 140)
            }
            Divider()
            Picker("Service", selection: $provider) {
                ForEach(StreamingServiceOption.catalog) { Text($0.name).tag($0.id) }
                Text("Other").tag("Other")
            }
            TextField("https://…", text: $url)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Link") {
                    store.attachLink(itemID: itemID, provider: provider, url: url)
                    url = ""
                }
                .buttonStyle(.borderedProminent).disabled(!validURL)
            }
        }
        .padding(24).frame(width: 590).frame(minHeight: 440)
    }
}

struct AddLibrarySheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let defaultCollectionID: String
    let onAdded: (String) -> Void
    @State private var addType = 0
    @State private var collectionName = ""
    @State private var collectionKind: CollectionKind = .films
    @State private var title = ""
    @State private var collectionID: String
    @State private var kind: MediaKind = .movie
    @State private var runtime = 120
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var season = 1
    @State private var episode = 1
    @State private var provider = "Disney+"
    @State private var providerURL = ""

    init(defaultCollectionID: String, onAdded: @escaping (String) -> Void = { _ in }) {
        self.defaultCollectionID = defaultCollectionID
        self.onAdded = onAdded
        _collectionID = State(initialValue: defaultCollectionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to Next Up").font(.title.bold())
                Text("Import a complete series or a poster-ready standalone movie.").foregroundStyle(.secondary)
            }
            Picker("Add", selection: $addType) {
                Text("Import Series").tag(0)
                Text("Import Movie").tag(1)
                Text("Add Manually").tag(2)
                Text("New Collection").tag(3)
            }.pickerStyle(.segmented)
            if addType == 0 {
                SeriesSearchAddView { importedCollectionID in
                    onAdded(importedCollectionID)
                    dismiss()
                }
            } else if addType == 1 {
                MovieSearchAddView { importedCollectionID in
                    onAdded(importedCollectionID)
                    dismiss()
                }
            } else {
                Form {
                if addType == 2 {
                    TextField("Title", text: $title)
                    Picker("Collection", selection: $collectionID) { ForEach(store.collections) { Text($0.name).tag($0.id) } }
                    Picker("Type", selection: $kind) { Text("Movie").tag(MediaKind.movie); Text("Episode").tag(MediaKind.episode); Text("Special").tag(MediaKind.special) }
                    Stepper("Runtime: \(runtime) minutes", value: $runtime, in: 1...600)
                    Stepper("Release year: \(year)", value: $year, in: 1888...2100)
                    if kind == .episode {
                        Stepper("Season: \(season)", value: $season, in: 1...100)
                        Stepper("Episode: \(episode)", value: $episode, in: 1...500)
                    }
                    Picker("Streaming service", selection: $provider) {
                        ForEach(StreamingServiceOption.catalog) { Text($0.name).tag($0.id) }
                        Text("Other").tag("Other")
                    }
                    TextField("Direct watch URL (optional)", text: $providerURL)
                } else {
                    TextField("Collection name", text: $collectionName)
                    Picker("Collection type", selection: $collectionKind) { Text("Film series").tag(CollectionKind.films); Text("TV series").tag(CollectionKind.series); Text("Queue").tag(CollectionKind.queue) }
                }
                }.formStyle(.grouped)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if addType >= 2 {
                    Button(addType == 2 ? "Add Title" : "Create Collection") { save(); dismiss() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
                }
            }
        }
        .padding(24).frame(width: 700).frame(minHeight: 590)
        .onAppear {
            if store.collection(collectionID) == nil { collectionID = store.collections.first?.id ?? "" }
        }
    }

    private var canSave: Bool {
        if addType == 2 { return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.collection(collectionID) != nil }
        return !collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        if addType == 2 {
            store.addItem(title: title, collectionID: collectionID, kind: kind, runtime: runtime, year: year, season: kind == .episode ? season : nil, episode: kind == .episode ? episode : nil, provider: provider, providerURL: providerURL.isEmpty ? nil : providerURL)
            onAdded(collectionID)
        } else {
            store.addCollection(name: collectionName, kind: collectionKind)
            if let created = store.collections.first(where: { $0.name.caseInsensitiveCompare(collectionName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
                onAdded(created.id)
            }
        }
    }
}

struct MovieSearchAddView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var query = ""
    @State private var results: [WatchmodeMovieSearchResult] = []
    @State private var isSearching = false
    @State private var importingID: Int?
    @State private var statusMessage: String?
    @FocusState private var searchFocused: Bool
    let imported: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search for a movie, such as The Godfather", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }

            if isSearching { ProgressView("Searching Watchmode…") }
            if let statusMessage {
                Label(statusMessage, systemImage: statusMessage.hasPrefix("Imported") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(statusMessage.hasPrefix("Imported") ? .green : .secondary)
            }

            if results.isEmpty && !isSearching {
                ContentUnavailableView {
                    Label("Import a Standalone Movie", systemImage: "popcorn.fill")
                } description: {
                    Text("Search by title. Next Up gives every standalone movie its own sidebar entry, poster, runtime, year, and current streaming links.")
                } actions: {
                    HStack {
                        suggestion("The Godfather")
                        suggestion("Everything Everywhere All at Once")
                        suggestion("Love & Basketball")
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { movie in
                            HStack(spacing: 13) {
                                AsyncImage(url: movie.artworkURL.flatMap(URL.init(string:))) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.12).overlay(Image(systemName: "film"))
                                }
                                .frame(width: 58, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(movie.title).font(.headline).lineLimit(2)
                                    Text(movie.year.map(String.init) ?? "Year unavailable")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if store.data.items.byID("watchmode-movie-\(movie.id)") != nil {
                                        Label("Already in Single Movies", systemImage: "checkmark.circle.fill")
                                            .font(.caption).foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                                Button(importingID == movie.id ? "Importing…" : "Add Movie") {
                                    importMovie(movie)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(importingID != nil)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
            }
            Text("Movie metadata and availability by Watchmode. Posters may be hosted by third parties.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            searchFocused = true
            if WatchmodeKeychain.load() == nil { statusMessage = "Add a Watchmode key in Settings before importing movies." }
        }
    }

    private func suggestion(_ title: String) -> some View {
        Button(title) { query = title; search() }.buttonStyle(.bordered)
    }

    private func search() {
        guard let key = WatchmodeKeychain.load() else {
            statusMessage = "Add a Watchmode key in Settings before importing movies."
            return
        }
        isSearching = true
        statusMessage = nil
        Task {
            do {
                results = try await WatchmodeService.searchMovies(query: query, key: key)
                if results.isEmpty { statusMessage = "No matching movies found. Try another title." }
            } catch {
                statusMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func importMovie(_ movie: WatchmodeMovieSearchResult) {
        guard let key = WatchmodeKeychain.load() else {
            statusMessage = "Add a Watchmode key in Settings before importing movies."
            return
        }
        importingID = movie.id
        statusMessage = nil
        Task {
            do {
                let details = try await WatchmodeService.movieDetails(id: movie.id, key: key)
                let accent: String
                if let artworkURL = details.artworkURL {
                    accent = await ArtworkPalette.accentHex(from: artworkURL, fallbackSeed: details.title)
                        ?? ArtworkPalette.fallbackAccent(for: details.title)
                } else {
                    accent = ArtworkPalette.fallbackAccent(for: details.title)
                }
                let collectionID = store.importWatchmodeMovie(details, accent: accent)
                statusMessage = "Imported \(details.title)."
                imported(collectionID)
            } catch {
                statusMessage = error.localizedDescription
                importingID = nil
            }
        }
    }
}

struct SeriesSearchAddView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var discovery = DiscoveryModel()
    @State private var query = ""
    @State private var importingID: Int?
    @State private var statusMessage: String?
    @FocusState private var searchFocused: Bool
    let imported: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search for a show, such as Attack on Titan", text: $query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || discovery.isLoading)
            }
            if discovery.isLoading { ProgressView("Searching for series…") }
            if let error = discovery.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
            if let statusMessage { Text(statusMessage).font(.callout).foregroundStyle(statusMessage.lowercased().contains("failed") ? .red : .green) }

            if discovery.results.isEmpty && !discovery.isLoading {
                ContentUnavailableView {
                    Label("Import a Complete Series", systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text("Search once, then Next Up creates the collection, seasons, episodes, runtimes, and progress tracking for you.")
                } actions: {
                    HStack {
                        suggestion("Attack on Titan")
                        suggestion("Big Brother")
                        suggestion("The Bear")
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(discovery.results.prefix(20))) { show in
                            HStack(spacing: 13) {
                                AsyncImage(url: show.image?.medium.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: {
                                    Color.secondary.opacity(0.12).overlay(Image(systemName: "tv"))
                                }
                                .frame(width: 58, height: 78).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(show.name).font(.headline)
                                    Text([show.premiered?.prefix(4).description, show.status].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    Text(show.plainSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Button(buttonTitle(show)) { importSeries(show) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(importingID != nil)
                            }
                            .padding(10).background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
            }
            HStack {
                Text("Series metadata by TVmaze (CC BY-SA). Streaming links can be added afterward.")
                Spacer()
            }.font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { searchFocused = true }
    }

    private func suggestion(_ title: String) -> some View {
        Button(title) { query = title; search() }.buttonStyle(.bordered)
    }

    private func search() { Task { await discovery.search(query) } }

    private func existingCollection(for show: TVMazeShow) -> MediaCollection? {
        store.collections.first {
            ($0.externalSource?.provider == "TVmaze" && $0.externalSource?.id == String(show.id)) || $0.name.caseInsensitiveCompare(show.name) == .orderedSame
        }
    }

    private func buttonTitle(_ show: TVMazeShow) -> String {
        if importingID == show.id { return "Importing…" }
        return existingCollection(for: show) == nil ? "Import All Episodes" : "Refresh & Open"
    }

    private func importSeries(_ show: TVMazeShow) {
        importingID = show.id
        statusMessage = "Fetching every episode of \(show.name)…"
        Task {
            do {
                let episodes = try await discovery.episodes(for: show)
                store.importTVMazeSeries(show: show, episodes: episodes)
                await store.refreshArtworkStylesIfNeeded()
                guard let collection = existingCollection(for: show) else { throw URLError(.cannotParseResponse) }
                imported(collection.id)
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
                importingID = nil
            }
        }
    }
}

func duration(_ minutes: Int) -> String {
    let hours = minutes / 60, mins = minutes % 60
    if hours == 0 { return "\(mins)m" }
    return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
}

func finishTime(_ minutes: Int) -> String {
    Date().addingTimeInterval(Double(minutes * 60)).formatted(date: .omitted, time: .shortened)
}

func itemMetadata(_ item: MediaItem) -> String {
    var parts: [String] = []
    if let season = item.season, let episode = item.episode { parts.append("S\(season) E\(episode)") }
    if let year = item.releaseYear { parts.append(String(year)) }
    if let rating = item.contentRating { parts.append(rating) }
    parts.append(duration(item.runtimeMinutes))
    return parts.joined(separator: " · ")
}

func openInSafari(_ item: MediaItem, link: ProviderLink) {
    guard let url = URL(string: link.url) else { return }
    if url.path.hasSuffix("/search") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.title, forType: .string)
    }
    let safari = URL(fileURLWithPath: "/Applications/Safari.app")
    NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        self.init(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, opacity: 1)
    }
}

private extension View {
    @ViewBuilder
    func librarySearchable(enabled: Bool, text: Binding<String>) -> some View {
        if enabled {
            searchable(text: text, placement: .toolbar, prompt: "Search library, movies & shows")
        } else {
            self
        }
    }
}
