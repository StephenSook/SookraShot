import AVFoundation
import AppKit
import CoreGraphics
import Testing
@testable import RecordingKit

@Suite struct RecordingEnhancerTests {
    /// Bakes a click ripple at an off-center click and checks a bright ripple
    /// pixel lands at the mapped video location (verifying the global -> video
    /// coordinate mapping, including the bottom-left -> image flip), while the
    /// frame center stays dark.
    @MainActor
    @Test func rippleRendersAtMappedLocation() async throws {
        let directory = FileManager.default.temporaryDirectory
        let sourceURL = directory.appendingPathComponent("fx-src-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try await Self.writeBlackVideo(to: sourceURL, size: 200, seconds: 2, fps: 30)

        // Region 200x200 at global origin (0,0). Click at global (150, 50)
        // -> normalized (0.75, 0.25) -> video bottom-left (150, 50)
        // -> top-left image point (150, 150).
        let click = RecordingClick(time: 0.5, location: CGPoint(x: 150, y: 50))
        let mapping = RecordingEnhancer.Mapping(
            regionOriginGlobal: .zero, regionSizeGlobal: CGSize(width: 200, height: 200)
        )
        let output = try await RecordingEnhancer().enhance(
            source: sourceURL, clicks: [click], mapping: mapping,
            toDirectory: directory, baseName: "fx-out-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: output) }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: 0.62, preferredTimescale: 600)).image
        let rep = NSBitmapImageRep(cgImage: frame)

        #expect(hasBrightYellow(in: rep, centerX: 150, centerY: 150, window: 18), "no ripple near the mapped point")
        #expect(!hasBrightYellow(in: rep, centerX: 100, centerY: 100, window: 8), "unexpected ripple at frame center")
    }

    private func hasBrightYellow(in rep: NSBitmapImageRep, centerX: Int, centerY: Int, window: Int) -> Bool {
        for x in (centerX - window)...(centerX + window) {
            for y in (centerY - window)...(centerY + window) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { continue }
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.5, color.greenComponent > 0.45, color.blueComponent < 0.5 {
                    return true
                }
            }
        }
        return false
    }

    private static func writeBlackVideo(to url: URL, size: Int, seconds: Int, fps: Int32) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size,
                AVVideoHeightKey: size,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
            context?.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: size, height: size))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
