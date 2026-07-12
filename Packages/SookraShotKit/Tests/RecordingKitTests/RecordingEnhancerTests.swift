import AVFoundation
import AppKit
import CoreGraphics
import Testing
@testable import RecordingKit

@Suite struct RecordingEnhancerTests {
    private static let mapping200 = RecordingEnhancer.Mapping(
        regionOriginGlobal: .zero, regionSizeGlobal: CGSize(width: 200, height: 200)
    )

    /// Bakes a click ripple at an off-center click and checks a bright ripple
    /// pixel lands at the mapped video location (global -> video mapping incl.
    /// the bottom-left -> image flip), while the frame center stays dark.
    @MainActor
    @Test func rippleRendersAtMappedLocation() async throws {
        let directory = FileManager.default.temporaryDirectory
        let sourceURL = directory.appendingPathComponent("fx-src-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try await Self.writeBlackVideo(to: sourceURL, size: 200, seconds: 2, fps: 30)

        let click = RecordingClick(time: 0.5, location: CGPoint(x: 150, y: 50))
        let output = try await RecordingEnhancer().enhance(
            source: sourceURL, clicks: [click], keystrokes: [], mapping: Self.mapping200,
            showRipples: true, autoZoom: false,
            toDirectory: directory, baseName: "fx-out-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: output) }

        let rep = try await Self.frame(of: output, at: 0.62)
        #expect(Self.hasBrightYellow(in: rep, centerX: 150, centerY: 150, window: 18), "no ripple near the mapped point")
        #expect(!Self.hasBrightYellow(in: rep, centerX: 100, centerY: 100, window: 8), "unexpected ripple at frame center")
    }

    /// A white marker at the frame center is enlarged during the zoom hold.
    @MainActor
    @Test func autoZoomEnlargesContent() async throws {
        let directory = FileManager.default.temporaryDirectory
        let sourceURL = directory.appendingPathComponent("fx-zoom-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try await Self.writeBlackVideo(to: sourceURL, size: 200, seconds: 2, fps: 30, marker: CGRect(x: 85, y: 85, width: 30, height: 30))

        let click = RecordingClick(time: 0.5, location: CGPoint(x: 100, y: 100))
        let output = try await RecordingEnhancer().enhance(
            source: sourceURL, clicks: [click], keystrokes: [], mapping: Self.mapping200,
            showRipples: false, autoZoom: true,
            toDirectory: directory, baseName: "fx-zoom-out-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: output) }

        let before = Self.whitePixelCount(in: try await Self.frame(of: output, at: 0.05))  // before the zoom window
        let zoomed = Self.whitePixelCount(in: try await Self.frame(of: output, at: 1.0))    // during the hold
        #expect(zoomed > Int(Double(before) * 1.4), "auto-zoom did not enlarge content: before=\(before) zoomed=\(zoomed)")
    }

    /// A keystroke shows up as a caption near the bottom-center of the frame.
    @MainActor
    @Test func keystrokeCaptionRenders() async throws {
        let directory = FileManager.default.temporaryDirectory
        let sourceURL = directory.appendingPathComponent("fx-keys-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try await Self.writeBlackVideo(to: sourceURL, size: 400, seconds: 2, fps: 30)

        let keys = [RecordingKeystroke(time: 0.5, display: "AB")]
        let output = try await RecordingEnhancer().enhance(
            source: sourceURL, clicks: [], keystrokes: keys, mapping: Self.mapping200,
            showRipples: false, autoZoom: false,
            toDirectory: directory, baseName: "fx-keys-out-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: output) }

        let rep = try await Self.frame(of: output, at: 0.9)
        // Bottom band in top-left image coords is high y for a 400px frame.
        #expect(Self.hasBrightWhite(in: rep, minX: 130, maxX: 270, minY: 345, maxY: 385), "no keystroke caption at bottom-center")
        #expect(!Self.hasBrightWhite(in: rep, minX: 0, maxX: 60, minY: 0, maxY: 40), "unexpected bright pixels at top corner")
    }

    // MARK: - Helpers

    private static func frame(of url: URL, at seconds: Double) async throws -> NSBitmapImageRep {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        return NSBitmapImageRep(cgImage: image)
    }

    private static func hasBrightYellow(in rep: NSBitmapImageRep, centerX: Int, centerY: Int, window: Int) -> Bool {
        for x in (centerX - window)...(centerX + window) {
            for y in (centerY - window)...(centerY + window) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.5, color.greenComponent > 0.45, color.blueComponent < 0.5 { return true }
            }
        }
        return false
    }

    private static func hasBrightWhite(in rep: NSBitmapImageRep, minX: Int, maxX: Int, minY: Int, maxY: Int) -> Bool {
        for x in minX...maxX {
            for y in minY...maxY {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.75, color.greenComponent > 0.75, color.blueComponent > 0.75 { return true }
            }
        }
        return false
    }

    private static func whitePixelCount(in rep: NSBitmapImageRep) -> Int {
        var count = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7, color.greenComponent > 0.7, color.blueComponent > 0.7 { count += 1 }
            }
        }
        return count
    }

    private static func writeBlackVideo(to url: URL, size: Int, seconds: Int, fps: Int32, marker: CGRect? = nil) async throws {
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
            if let marker {
                context?.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context?.fill(marker)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
