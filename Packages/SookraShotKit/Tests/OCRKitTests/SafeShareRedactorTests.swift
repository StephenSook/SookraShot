import AppKit
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OCRKit

@Suite struct SafeShareRedactorTests {
    /// Renders a line containing an email, redacts, and checks that at least
    /// one region was blacked out.
    @Test func redactsDetectedEmail() async throws {
        let size = NSSize(width: 700, height: 140)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            "Contact jane@example.com".draw(
                at: NSPoint(x: 30, y: 50),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
                    .foregroundColor: NSColor.black,
                ]
            )
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: size)
        let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))

        let result = try await SafeShareRedactor().redact(cgImage, redactFaces: false)
        #expect(result.redactedCount >= 1)

        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("sookrashot-redact-preview.png")
        let data = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, result.image, nil)
            CGImageDestinationFinalize(dest)
            try (data as Data).write(to: previewURL)
        }
    }
}
