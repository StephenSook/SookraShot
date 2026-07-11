import CoreGraphics
import Foundation
import Vision

/// On-device OCR via Apple Vision — same engine as macOS Live Text.
public struct RecognizedText: Sendable {
    public struct Line: Sendable {
        public let text: String
        /// Normalized (0-1) bounding box, origin bottom-left (Vision convention).
        public let boundingBox: CGRect
    }

    public let lines: [Line]

    public var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// Single-line variant (line breaks replaced with spaces) — CleanShot parity.
    public var fullTextWithoutLineBreaks: String {
        lines.map(\.text).joined(separator: " ")
    }
}

public struct TextRecognizer: Sendable {
    public init() {}

    public func recognizeText(in image: CGImage) async throws -> RecognizedText {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation -> RecognizedText.Line? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedText.Line(text: candidate.string, boundingBox: observation.boundingBox)
                }
                continuation.resume(returning: RecognizedText(lines: lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
