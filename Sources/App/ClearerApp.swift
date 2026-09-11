import SwiftData
import SwiftUI

@main
struct ClearerApp: App {
    // Two model types now (analysis cache + review progress), so the
    // container is built explicitly instead of the single-type
    // `.modelContainer(for:)` scene modifier shorthand.
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: AssetAnalysis.self, ReviewProgressRecord.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
