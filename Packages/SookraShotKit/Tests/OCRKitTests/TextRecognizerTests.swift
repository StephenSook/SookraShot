import AppKit
import Testing
@testable import OCRKit

@Suite struct TextRecognizerTests {
    /// End-to-end Vision OCR against a synthetic rendered image.
    @Test func recognizesRenderedText() async throws {
        let size = NSSize(width: 600, height: 120)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            "SookraShot 12345".draw(
                at: NSPoint(x: 40, y: 40),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
                    .foregroundColor: NSColor.black,
                ]
            )
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: size)
        let cgImage = try #require(
            image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )

        let recognized = try await TextRecognizer().recognizeText(in: cgImage)
        #expect(recognized.fullText.contains("SookraShot"))
    }
}
