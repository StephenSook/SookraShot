import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExportError: Error, Sendable {
    case noVideoTrack
    case destinationFailed
}

/// Converts a recorded MP4 into an animated GIF (sampled frames, capped width).
public struct GIFExporter: Sendable {
    public var framesPerSecond: Double
    public var maxWidth: CGFloat

    public init(framesPerSecond: Double = 10, maxWidth: CGFloat = 960) {
        self.framesPerSecond = framesPerSecond
        self.maxWidth = maxWidth
    }

    public func exportGIF(from videoURL: URL, to gifURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw GIFExportError.noVideoTrack }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let frameCount = max(Int(duration * framesPerSecond), 1)
        let times = (0..<frameCount).map { index in
            CMTime(seconds: Double(index) / framesPerSecond, preferredTimescale: 600)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else {
            throw GIFExportError.destinationFailed
        }

        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1.0 / framesPerSecond
            ]
        ]

        for time in times {
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFExportError.destinationFailed
        }
    }
}
