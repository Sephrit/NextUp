import SwiftUI

@main
struct NextUpApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup("Next Up") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 360, minHeight: 540)
        }
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .undoRedo) {
                Button("Undo Last Library Change") { store.undoLastChange() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Library") {
                Button("Export Backup…") { store.exportLibrary() }
                Button("Restore Backup…") { store.importLibrary() }
                Divider()
                Button("Show Library File") { store.revealDataFolder() }
            }
        }
    }
}

enum DetailMode: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case list = "Checklist"
    case rankings = "Rankings"
    case log = "Watch Log"
    case discover = "Discover"
    case watchable = "Watchable"
    var id: String { rawValue }

    static let collectionViews: [DetailMode] = [.overview, .list, .rankings, .log]
    static let exploreViews: [DetailMode] = [.discover, .watchable]
    var isExplore: Bool { Self.exploreViews.contains(self) }
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var collectionID = "star-wars"
    @State private var orderID = "star-wars-release"
    @State private var mode: DetailMode = .overview
    @State private var ratingItemID: String?
    @State private var showingAdd = false
    @State private var showingSetup = false
    @State private var showingSettings = false
    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width < 650 {
                    CompactView(collectionID: $collectionID, orderID: $orderID, onRate: { ratingItemID = $0 }, onAdd: { showingAdd = true }, onSettings: { showingSettings = true })
                } else {
                    FullView(collectionID: $collectionID, orderID: $orderID, mode: $mode, onRate: { ratingItemID = $0 }, onAdd: { showingAdd = true }, onSettings: { showingSettings = true })
                }
            }
        }
        .onReceive(refreshTimer) { _ in store.refreshIfChanged() }
        .onAppear { showingSetup = store.data.setupComplete != true }
        .task {
            await store.refreshArtworkStylesIfNeeded()
            await store.refreshMovieRatingsIfNeeded()
        }
        .onChange(of: collectionID) { _, newValue in
            orderID = store.collection(newValue)?.orders.first?.id ?? ""
        }
        .sheet(item: Binding(
            get: { ratingItemID.map { IdentifiedString(value: $0) } },
            set: { ratingItemID = $0?.value }
        )) { value in
            RatingSheet(itemID: value.value)
        }
        .sheet(isPresented: $showingAdd) {
            AddLibrarySheet(defaultCollectionID: collectionID) { addedCollectionID in
                collectionID = addedCollectionID
                orderID = store.collection(addedCollectionID)?.orders.first?.id ?? ""
                mode = .list
            }
        }
        .sheet(isPresented: $showingSetup) {
            FirstRunSheet { first, second, providers, keepStarter in
                store.completeSetup(firstProfile: first, secondProfile: second, providers: providers, keepStarterLibrary: keepStarter)
                showingSetup = false
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSettings) {
            ProfileSettingsSheet()
        }
    }
}

struct IdentifiedString: Identifiable {
    let id = UUID()
    let value: String
}
