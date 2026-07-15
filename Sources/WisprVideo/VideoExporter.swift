import AVFoundation
import AppKit

/// One social-media output target.
struct ExportSpec: Sendable {
    let label: String
    let ratio: String
    let fileName: String
    let width: Int
    let height: Int
}

enum VideoExporter {
    static let specs: [ExportSpec] = [
        ExportSpec(label: "Vertical",  ratio: "9:16", fileName: "vertical-9x16",  width: 1080, height: 1920),
        ExportSpec(label: "Portrait",  ratio: "4:5",  fileName: "portrait-4x5",   width: 1080, height: 1350),
        ExportSpec(label: "Square",    ratio: "1:1",  fileName: "square-1x1",     width: 1080, height: 1080),
        ExportSpec(label: "Landscape", ratio: "16:9", fileName: "landscape-16x9", width: 1920, height: 1080),
    ]

    /// Renders `source` into `spec`'s size using a center-crop-to-fill transform.
    static func export(source: URL, spec: ExportSpec, outputDir: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "WisprVideo", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No video track found."])
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)

        let target = CGSize(width: spec.width, height: spec.height)

        // Size after the track's orientation transform (translation ignored for a size vector).
        let oriented = naturalSize.applying(preferred)
        let displayW = abs(oriented.width)
        let displayH = abs(oriented.height)

        let scale = max(target.width / displayW, target.height / displayH)
        let scaledW = displayW * scale
        let scaledH = displayH * scale
        let tx = (target.width - scaledW) / 2
        let ty = (target.height - scaledH) / 2

        var transform = preferred
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: tx, y: ty))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = target
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let outURL = outputDir.appendingPathComponent(spec.fileName + ".mp4")
        try? FileManager.default.removeItem(at: outURL)

        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "WisprVideo", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create export session."])
        }
        export.outputURL = outURL
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.shouldOptimizeForNetworkUse = true

        return try await withCheckedThrowingContinuation { continuation in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    continuation.resume(returning: outURL)
                default:
                    continuation.resume(throwing: export.error
                        ?? NSError(domain: "WisprVideo", code: 3,
                                   userInfo: [NSLocalizedDescriptionKey: "Export failed."]))
                }
            }
        }
    }

    /// Grabs a representative frame for a thumbnail.
    static func thumbnail(for url: URL, maxDim: CGFloat = 480) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDim, height: maxDim)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
