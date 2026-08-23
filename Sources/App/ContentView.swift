import SwiftUI

/// Routes between the permission gate and the photo grid, and re-checks
/// authorization whenever the app comes back to the foreground (in case the
/// user granted access from Settings while we were backgrounded).
struct ContentView: View {
    @State private var model = PhotoGridModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.authorizationStatus {
            case .authorized, .limited:
                // Only the grid gets a NavigationStack — the gate screen
                // stays exactly as it was, with no stray empty nav bar
                // above its centered content.
                NavigationStack {
                    PhotoGridView(model: model)
                }
            default:
                PhotoAccessGateView(status: model.authorizationStatus) {
                    Task { await model.requestAccess() }
                }
            }
        }
        .task {
            model.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.refreshAuthorizationStatus()
            }
        }
    }
}

#Preview {
    ContentView()
}
