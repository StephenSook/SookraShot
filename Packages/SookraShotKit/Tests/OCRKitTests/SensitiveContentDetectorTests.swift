import CoreGraphics
import Testing
@testable import OCRKit

@Suite struct SensitiveContentDetectorTests {
    private func recognized(_ lines: [String]) -> RecognizedText {
        RecognizedText(
            lines: lines.enumerated().map { index, text in
                RecognizedText.Line(
                    text: text,
                    boundingBox: CGRect(x: 0.1, y: 0.1 * Double(index), width: 0.8, height: 0.05)
                )
            }
        )
    }

    @Test func detectsEmail() {
        let matches = SensitiveContentDetector().detect(in: recognized(["contact stephen@example.com now"]))
        #expect(matches.contains { $0.kind == .email && $0.text == "stephen@example.com" })
    }

    @Test func detectsVendorAPIKeys() {
        let lines = [
            "STRIPE_KEY=sk-abc123def456ghi789jkl012",
            "token ghp_abcdefghijklmnopqrstuvwxyz123456",
            "aws AKIAIOSFODNN7EXAMPLE",
        ]
        let matches = SensitiveContentDetector().detect(in: recognized(lines))
        #expect(matches.filter { $0.kind == .apiKey }.count == 3)
    }

    @Test func detectsSSN() {
        let matches = SensitiveContentDetector().detect(in: recognized(["ssn 078-05-1120"]))
        #expect(matches.contains { $0.kind == .ssn })
    }

    @Test func luhnRejectsRandomDigitRuns() {
        let matches = SensitiveContentDetector().detect(in: recognized(["order 1234 5678 9012 3456 7"]))
        #expect(!matches.contains { $0.kind == .creditCard })
    }

    @Test func luhnAcceptsValidCardNumber() {
        let matches = SensitiveContentDetector().detect(in: recognized(["card 4111 1111 1111 1111"]))
        #expect(matches.contains { $0.kind == .creditCard })
    }

    @Test func cleanTextProducesNoMatches() {
        let matches = SensitiveContentDetector().detect(in: recognized(["just a normal sentence"]))
        #expect(matches.isEmpty)
    }
}
