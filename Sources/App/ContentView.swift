import SwiftUI

/// Placeholder screen for Fase 0. The real onboarding/UI arrives in later
/// fases — this just proves the app target builds, launches, and renders.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(AppInfo.name)
                .font(.largeTitle.weight(.semibold))
            Text("Scaffolding en pie. La app de verdad empieza en la Fase 1.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
