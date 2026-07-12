import Foundation

/// Derives a filename from recognized text so a saved screenshot can be named
/// from its content (e.g. "stripe-dashboard-invoices") instead of a timestamp.
public enum SmartFilename {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "is", "are",
        "with", "your", "you", "this", "that", "from", "at", "by", "it",
    ]

    public static func suggest(from recognized: RecognizedText, maxWords: Int = 6) -> String? {
        var words: [String] = []
        outer: for line in recognized.lines {
            for token in line.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let word = token.lowercased()
                guard word.count >= 2, !stopWords.contains(word) else { continue }
                words.append(word)
                if words.count >= maxWords { break outer }
            }
        }
        guard !words.isEmpty else { return nil }
        return words.joined(separator: "-")
    }
}
