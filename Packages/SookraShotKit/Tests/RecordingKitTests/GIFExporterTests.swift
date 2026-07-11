import AVFoundation
import CoreGraphics
import ImageIO
import Testing
@testable import RecordingKit

@Suite struct GIFExporterTests {
    /// Builds a 1-second synthetic H.264 clip, exports a GIF, checks frames.
    @Test func exportsAnimatedGIFFromVideo() async throws {
        let directory = FileManager.default.temporaryDirectory
        let videoURL = directory.appendingPathComponent("gif-test-\(UUID().uuidString).mp4")
        let gifURL = directory.appendingPathComponent("gif-test-\(UUID().uuidString).gif")
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: gifURL)
        }

        try await Self.writeSyntheticVideo(to: videoURL, width: 320, height: 200, frames: 12, fps: 12)

        try await GIFExporter(framesPerSecond: 6, maxWidth: 320).exportGIF(from: videoURL, to: gifURL)

        let source = try #require(CGImageSourceCreateWithURL(gifURL as CFURL, nil))
        let frameCount = CGImageSourceGetCount(source)
        #expect(frameCount >= 3)
        #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
    }

    private static func writeSyntheticVideo(
        to url: URL,
        width: Int,
        height: Int,
        frames: Int,
        fps: Int32
    ) async throws {
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
