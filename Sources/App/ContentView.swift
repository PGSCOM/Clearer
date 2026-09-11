import SwiftData
import SwiftUI

/// Routes between onboarding, the denied-access recovery screen, and the
/// two top-level modes — and re-checks authorization whenever the app comes
/// back to the foreground (in case the user granted access from Settings
/// while we were backgrounded).
struct ContentView: View {
    @State private var model = PhotoGridModel()
    @State private var coordinator: AnalysisCoordinator?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch model.authorizationStatus {
            case .authorized, .limited:
                // Only the two modes get a NavigationStack each — the other
                // two screens stay full-bleed, with no stray empty nav bar
                // above their content. One shared coordinator, so both tabs
                // stage deletions into the same trash.
                if let coordinator {
                    TabView {
                        Tab("Fotos", systemImage: "photo.on.rectangle") {
                            NavigationStack {
                                PhotoGridView(model: model, coordinator: coordinator)
                            }
                        }
                        Tab("Vídeos", systemImage: "video") {
                            NavigationStack {
                                VideoModeView(coordinator: coordinator)
                            }
                        }
                    }
                }
            case .denied, .restricted:
                AccessDeniedView()
            default:
                OnboardingView {
                    Task { await model.requestAccess() }
                }
            }
        }
        .task {
            model.refreshAuthorizationStatus()
            if coordinator == nil {
                coordinator = AnalysisCoordinator(modelContext: modelContext)
            }
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
