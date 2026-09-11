import AVFoundation
import CoreMedia

/// Shrinks a video's resolution while keeping its bitrate and color space
/// exactly as recorded — only the pixel dimensions change. Built on
/// `AVAssetReader`/`AVAssetWriter` rather than `AVAssetExportSession`: export
/// sessions only offer fixed quality presets, with no way to pin an exact
/// target bitrate or hand the source's color primaries/transfer
/// function/YCbCr matrix straight through, and both are the whole point
/// here. PhotoKit-agnostic on purpose — it only touches `AVAsset`, so
/// `PhotoLibrary.swift` stays the one file that talks to PhotoKit itself.
///
/// ponytail: the resize goes through `AVMutableVideoComposition`'s Core
/// Animation compositor, which works in 8-bit. A 10-bit HDR (Dolby
/// Vision/HLG) source still gets its color tags preserved correctly, but
/// loses bit depth in the process — true 10-bit passthrough needs a custom
/// `AVVideoCompositing` class driven by Metal. Revisit if HDR fidelity on
/// recoded video turns out to matter in practice.
enum VideoRecoder {
    enum RecodeError: Error {
        case noVideoTrack
        case alreadySmallEnough
        case readerFailed(String)
        case writerFailed(String)
    }

    /// Long-edge target in pixels. Recoding only ever downscales — a video
    /// already at or under the target throws `alreadySmallEnough`. Declared
    /// largest-first so `allCases` feeds a menu that's already in the right
    /// order.
    enum Target: CaseIterable, Identifiable {
        case p2160
        case p1440
        case p1080
        case p720
        case p540

        var longEdge: CGFloat {
            switch self {
            case .p2160: 3840
            case .p1440: 2560
            case .p1080: 1920
            case .p720: 1280
            case .p540: 960
            }
        }

        var id: Self { self }

        var label: String {
            switch self {
            case .p2160: "2160p"
            case .p1440: "1440p"
            case .p1080: "1080p"
            case .p720: "720p"
            case .p540: "540p"
            }
        }
    }

    /// Recodes `asset`'s video track into `outputURL` (must not already
    /// exist) at `target`'s long edge, preserving orientation, bitrate,
    /// codec and color space. Audio is copied through untouched, no
    /// re-encode. `onProgress` reports 0...1 against the track's duration.
    static func recode(
        _ asset: AVAsset,
        to target: Target,
        outputURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecodeError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let visualSize = naturalSize.applying(transform)
        let absSize = CGSize(width: abs(visualSize.width), height: abs(visualSize.height))
        let longEdge = max(absSize.width, absSize.height)
        guard longEdge > target.longEdge else { throw RecodeError.alreadySmallEnough }

        let scale = target.longEdge / longEdge
        let outputSize = CGSize(width: CGFloat(evenInt(absSize.width * scale)), height: CGFloat(evenInt(absSize.height * scale)))

        let estimatedBitRate = try await videoTrack.load(.estimatedDataRate)
        // A handful of sources don't report a data rate at all; fall back to
        // a sane default rather than writing a 0 bps track.
        let averageBitRate = estimatedBitRate > 0 ? Int(estimatedBitRate) : 8_000_000

        let formatDescription = try await videoTrack.load(.formatDescriptions).first
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codecType(from: formatDescription),
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: averageBitRate],
        ]
        if let colorProperties = colorProperties(from: formatDescription) {
            videoSettings[AVVideoColorPropertiesKey] = colorProperties
        }

        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let composition = AVMutableVideoComposition()
        composition.renderSize = outputSize
        composition.frameDuration = nominalFrameRate > 0
            ? CMTime(value: 1, timescale: Int32(nominalFrameRate.rounded()))
            : CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        // Original orientation transform, then the uniform downscale —
        // order doesn't matter for a uniform scale, so no swapped-axis trap.
        layerInstruction.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw RecodeError.readerFailed(error.localizedDescription)
        }

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        )
        videoOutput.videoComposition = composition
        guard reader.canAdd(videoOutput) else { throw RecodeError.readerFailed("no se pudo leer el vídeo") }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw RecodeError.writerFailed("no se pudo escribir el vídeo") }
        writer.add(videoInput)

        var audioPair: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil) // passthrough, no re-encode
            let formatHint = try await audioTrack.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formatHint)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioPair = (output, input)
            }
        }

        guard reader.startReading() else {
            throw RecodeError.readerFailed(reader.error?.localizedDescription ?? "error desconocido")
        }
        guard writer.startWriting() else {
            throw RecodeError.writerFailed(writer.error?.localizedDescription ?? "error desconocido")
        }
        writer.startSession(atSourceTime: .zero)

        let durationSeconds = duration.seconds
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await drain(videoOutput, into: videoInput, queueLabel: "video") { sample in
                        guard durationSeconds > 0 else { return }
                        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        onProgress(min(max(time / durationSeconds, 0), 1))
                    }
                }
                if let audioPair {
                    group.addTask {
                        try await drain(audioPair.output, into: audioPair.input, queueLabel: "audio")
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw RecodeError.writerFailed(writer.error?.localizedDescription ?? "error desconocido")
        }
        onProgress(1)
    }

    /// Drives one reader/writer pair to completion — video and audio each
    /// run this on their own queue, in parallel, via the `TaskGroup` above.
    private static func drain(
        _ output: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        queueLabel: String,
        onSample: (@Sendable (CMSampleBuffer) -> Void)? = nil
    ) async throws {
        let queue = DispatchQueue(label: "com.pablogarcia.clearer.recode.\(queueLabel)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sample = output.copyNextSampleBuffer() {
                        onSample?(sample)
                        if !input.append(sample) {
                            input.markAsFinished()
                            continuation.resume(throwing: RecodeError.writerFailed("no se pudo escribir un fotograma"))
                            return
                        }
                    } else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    private static func evenInt(_ value: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }

    private static func codecType(from formatDescription: CMFormatDescription?) -> AVVideoCodecType {
        guard let formatDescription else { return .hevc }
        return CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_H264 ? .h264 : .hevc
    }

    /// Reads the source's color primaries/transfer function/YCbCr matrix
    /// straight off its format description and hands them back verbatim —
    /// `CMFormatDescription`'s extension values use the same string
    /// constants as `AVVideoColorPropertiesKey`, so no translation is
    /// needed. nil (the encoder's own default) if the source doesn't tag
    /// them at all.
    private static func colorProperties(from formatDescription: CMFormatDescription?) -> [String: Any]? {
        guard let formatDescription,
              let primaries = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String,
              let transfer = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String,
              let matrix = CMFormatDescriptionGetExtension(formatDescription, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String
        else { return nil }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
    }
}

extension VideoRecoder.RecodeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "El vídeo no tiene pista de imagen."
        case .alreadySmallEnough: "Ya está en esta resolución o por debajo."
        case .readerFailed(let message), .writerFailed(let message): message
        }
    }
}
