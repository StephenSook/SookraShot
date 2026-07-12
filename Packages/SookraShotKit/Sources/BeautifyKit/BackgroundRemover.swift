import CoreGraphics
import CoreImage
import Vision

/// Cuts the salient foreground subject out of a capture, leaving a transparent
/// background (Vision's foreground instance mask, on-device).
public struct BackgroundRemover: Sendable {
    private struct SendableImage: @unchecked Sendable {
        let image: CGImage
    }

    public init() {}

    /// Returns the subject on a transparent background, or nil if Vision finds
    /// no foreground subject. Runs off the main thread.
    public func removeBackground(from image: CGImage) async throws -> CGImage? {
        let input = SendableImage(image: image)
        let output: SendableImage? = try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: input.image)
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return SendableImage(image: cgImage)
        }.value
        return output?.image
    }
}
