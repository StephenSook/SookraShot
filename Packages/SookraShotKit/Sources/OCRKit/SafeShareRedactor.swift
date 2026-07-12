import CoreGraphics
import Foundation
import Vision

/// One-shot redaction for safe sharing: finds secrets/PII (and optionally
/// faces) and blacks out those regions, without opening the annotate editor.
public struct SafeShareRedactor: Sendable {
    public struct Result: Sendable {
        public let image: CGImage
        public let redactedCount: Int
    }

    public init() {}

    public func redact(_ image: CGImage, redactFaces: Bool = true) async throws -> Result {
        let recognized = try await TextRecognizer().recognizeText(in: image)
        let matches = SensitiveContentDetector().detect(in: recognized)
        var boxes = matches.map(\.boundingBox)

        if redactFaces {
            boxes.append(contentsOf: detectFaces(in: image))
        }

        guard !boxes.isEmpty else {
            return Result(image: image, redactedCount: 0)
        }

        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Result(image: image, redactedCount: 0)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))

        // Vision boxes are normalized, bottom-left origin — same as CGContext.
        let padX = CGFloat(width) * 0.006
        let padY = CGFloat(height) * 0.006
        for box in boxes {
            let rect = CGRect(
                x: box.minX * CGFloat(width) - padX,
                y: box.minY * CGFloat(height) - padY,
                width: box.width * CGFloat(width) + padX * 2,
                height: box.height * CGFloat(height) + padY * 2
            )
            context.fill(rect.integral)
        }

        guard let output = context.makeImage() else {
            return Result(image: image, redactedCount: 0)
        }
        return Result(image: output, redactedCount: boxes.count)
    }

    private func detectFaces(in image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).map(\.boundingBox)
    }
}
