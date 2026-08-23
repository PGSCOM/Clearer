import Photos
import SwiftUI
import UIKit

/// Shown instead of the grid until we have permission to read the photo
/// library. Three states: ask, or point at Settings when denied/restricted.
struct PhotoAccessGateView: View {
    let status: PHAuthorizationStatus
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Acceso a tus fotos")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: primaryAction) {
                Text(buttonTitle)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var message: String {
        switch status {
        case .denied, .restricted:
            "Has denegado el acceso a fotos. Actívalo en Ajustes para que Clearer pueda revisar tu fototeca."
        default:
            "Clearer necesita ver tus fotos para ayudarte a encontrar las que sobran. Nunca las sube a ningún sitio, y las que están solo en iCloud no se descargan."
        }
    }

    private var buttonTitle: String {
        status == .notDetermined ? "Dar acceso" : "Abrir Ajustes"
    }

    private func primaryAction() {
        if status == .notDetermined {
            onRequestAccess()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
