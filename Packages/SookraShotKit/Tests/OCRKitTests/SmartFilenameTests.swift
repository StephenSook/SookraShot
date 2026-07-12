import CoreGraphics
import Testing
@testable import OCRKit

@Suite struct SmartFilenameTests {
    private func recognized(_ lines: [String]) -> RecognizedText {
        RecognizedText(lines: lines.map { RecognizedText.Line(text: $0, boundingBox: .zero) })
    }

    @Test func buildsSlugFromContent() {
        let name = SmartFilename.suggest(from: recognized(["Stripe Dashboard", "Invoices for March"]))
        #expect(name == "stripe-dashboard-invoices-march")
    }

    @Test func capsWordCount() {
        let name = SmartFilename.suggest(from: recognized(["one two three four five six seven eight"]), maxWords: 3)
        #expect(name == "one-two-three")
    }

    @Test func nilWhenNoUsableWords() {
        #expect(SmartFilename.suggest(from: recognized(["", "a to"])) == nil)
    }
}
