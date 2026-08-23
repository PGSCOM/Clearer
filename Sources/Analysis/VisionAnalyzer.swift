import CoreImage
import UIKit
import Vision

/// Result of running Vision on one already-fetched thumbnail. Never touches
/// PhotoKit or the network — everything here works on pixels already in
/// memory.
struct VisionAnalysisResult {
    /// -1...1, higher is more aesthetically pleasing. Vision's own quality
    /// model already factors in blur, exposure and composition, so this
    /// doubles as the "badly taken / blurry" signal — no separate
    /// hand-rolled sharpness pass needed.
    let overallScore: Float
    /// True for screenshots, receipts, documents — well-composed but not a
    /// memorable photo, per Vision's own aesthetics model.
    let isUtility: Bool
    /// Compact vector for near-duplicate comparison via
    /// `VNFeaturePrintObservation.computeDistance`. nil if generation
    /// failed — analysis still proceeds with just the aesthetics result.
    let featurePrint: VNFeaturePrintObservation?
}

enum VisionAnalyzer {
    /// Not actor- or MainActor-isolated on purpose: this does real ML
    /// inference (slow-ish, CPU/ANE-bound), and an `async` function with no
    /// isolation annotation runs on Swift's cooperative background pool,
    /// keeping it off the main thread automatically.
    static func analyze(_ image: UIImage) async -> VisionAnalysisResult? {
        guard let cgImage = image.cgImage else { return nil }

        let featurePrint = featurePrint(for: cgImage)

        let ciImage = CIImage(cgImage: cgImage)
        guard let aesthetics = try? await CalculateImageAestheticsScoresRequest().perform(on: ciImage) else {
            return nil
        }

        return VisionAnalysisResult(
            overallScore: aesthetics.overallScore,
            isUtility: aesthetics.isUtility,
            featurePrint: featurePrint
        )
    }

    /// The classic (non-async) Vision request API, deliberately — it's been
    /// stable and consistently documented since iOS 13, unlike the newer
    /// no-VN-prefix Swift request types, whose exact shape for feature
    /// prints wasn't pinned down with enough confidence to bet on blind
    /// (no local Xcode to check against). `VNImageRequestHandler.perform`
    /// is synchronous, which is fine here since this whole function
    /// already runs off the main thread.
    private static func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }
}
