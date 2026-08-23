import SwiftData
import SwiftUI

@main
struct ClearerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: AssetAnalysis.self)
    }
}
