import SwiftUI
import UIKit

/// Shown only for `.denied`/`.restricted` — a returning user who already
/// saw the onboarding pitch, so this stays short and just points at
/// Settings instead of repeating it.
struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Sin acceso a tus fotos")
                .font(.title2.weight(.semibold))
            Text("Has denegado el acceso a fotos. Actívalo en Ajustes para que Clearer pueda revisar tu fototeca.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.amberFilled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    AccessDeniedView()
}
