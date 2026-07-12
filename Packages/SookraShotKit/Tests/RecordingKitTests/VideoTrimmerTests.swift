import AVFoundation
import CoreGraphics
import Testing
@testable import RecordingKit

@Suite struct VideoTrimmerTests {
    /// Builds a 3-second synthetic clip, trims [1s, 2s], and checks the
    /// exported clip is ~1 second long.
    @Test func exportsRequestedTimeRange() async throws {
        let directory = FileManager.default.temporaryDirectory
        let sourceURL = directory.appendingPathComponent("trim-src-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        try await Self.writeSyntheticVideo(to: sourceURL, seconds: 3, fps: 12)

        let range = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 600),
            end: CMTime(seconds: 2, preferredTimescale: 600)
        )
        let base = "trim-out-\(UUID().uuidString)"
        let output = try await VideoTrimmer().export(
            source: sourceURL, timeRange: range, toDirectory: directory, baseName: base
        )
        defer { try? FileManager.default.removeItem(at: output) }

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(duration > 0.8 && duration < 1.2, "trimmed duration was \(duration)s")
    }

    private static func writeSyntheticVideo(to url: URL, seconds: Int, fps: Int32) async throws {
        let width = 320, height = 200
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frames = seconds * Int(fps)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
            let hue = CGFloat(frame) / CGFloat(frames)
            context?.setFillColor(CGColor(srgbRed: hue, green: 0.4, blue: 1 - hue, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
