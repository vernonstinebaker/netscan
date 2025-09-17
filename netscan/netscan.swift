import SwiftUI
import SwiftData

@main
struct netscan: App {
    // Preload OUI/vendor DB on startup to make vendor lookups immediate
    init() {
        Task {
            await OUILookupService.shared.preload()
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PersistentDevice.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: sharedModelContainer.mainContext)
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
