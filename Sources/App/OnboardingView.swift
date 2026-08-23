import SwiftUI

/// First-run only: brand + value prop, then the privacy explanation BEFORE
/// the system permission prompt fires — never the system dialog cold, with
/// no context. Fixed dark pine background regardless of system appearance:
/// a deliberate one-time brand moment, not a surface that needs to blend in.
struct OnboardingView: View {
    let onRequestAccess: () -> Void

    @State private var step = 0

    var body: some View {
        ZStack {
            Color.clearerPine.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $step) {
                    WelcomeStep().tag(0)
                    PrivacyStep(onRequestAccess: onRequestAccess).tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.bottom, 28)

                if step == 0 {
                    Button("Continuar") {
                        withAnimation { step = 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.clearerAmber)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.clearerCream : Color.clearerCream.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            FannedCardsView()
                .scaleEffect(1.4)
            VStack(spacing: 10) {
                Text("Clearer")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.clearerCream)
                Text("Encuentra lo que sobra en tu fototeca sin que ninguna foto salga de tu iPhone.")
                    .font(.body)
                    .foregroundStyle(Color.clearerCream.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Spacer()
        }
    }
}

private struct PrivacyStep: View {
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(alignment: .leading, spacing: 22) {
                point("El análisis pasa en tu iPhone. Nunca se sube nada a ningún sitio.")
                point("Las fotos que solo están en iCloud no se descargan para analizarlas.")
                point("Tú decides qué se borra — nada se elimina sin que lo confirmes dos veces.")
            }
            .padding(.horizontal, 32)
            Spacer()
            Button("Dar acceso a mis fotos") {
                onRequestAccess()
            }
            .buttonStyle(.borderedProminent)
            .tint(.clearerAmber)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(Color.clearerAmber)
                .frame(width: 7, height: 7)
                .padding(.top, 7)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.clearerCream)
        }
    }
}

#Preview {
    OnboardingView(onRequestAccess: {})
}
