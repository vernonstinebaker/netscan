import Foundation
import SwiftData

@MainActor
public final class DataManager {
    public static let shared = DataManager()
    
    public let modelContainer: ModelContainer
    
    private init() {
        let schema = Schema([
            PersistentDevice.self,
            // Vendor.self has been removed
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}