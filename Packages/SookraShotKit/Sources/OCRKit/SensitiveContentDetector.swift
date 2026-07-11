import CoreGraphics
import Foundation

/// Flags secrets and PII in recognized text so the editor can auto-redact them.
/// All on-device; nothing leaves the machine.
public struct SensitiveMatch: Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case email
        case apiKey
        case creditCard
        case ssn
        case phone
        case ipAddress
    }

    public let kind: Kind
    public let text: String
    /// Normalized bounding box of the OCR line containing the match (Vision convention).
    public let boundingBox: CGRect
}

public struct SensitiveContentDetector: Sendable {
    public init() {}

    private static let patterns: [(SensitiveMatch.Kind, String)] = [
        (.email, #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
        // Vendor-prefixed keys plus generic long tokens.
        (.apiKey, #"\b(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[bapr]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|Bearer\s+[A-Za-z0-9._~+/-]{20,}=*)"#),
        (.creditCard, #"\b(?:\d[ -]?){13,19}\b"#),
        (.ssn, #"\b\d{3}-\d{2}-\d{4}\b"#),
        (.phone, #"\b(?:\+1[ .-]?)?\(?\d{3}\)?[ .-]?\d{3}[ .-]?\d{4}\b"#),
        (.ipAddress, #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
    ]

    public func detect(in recognized: RecognizedText) -> [SensitiveMatch] {
        var matches: [SensitiveMatch] = []
        for line in recognized.lines {
            for (kind, pattern) in Self.patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(line.text.startIndex..., in: line.text)
                for result in regex.matches(in: line.text, range: range) {
                    guard let swiftRange = Range(result.range, in: line.text) else { continue }
                    let text = String(line.text[swiftRange])
                    if kind == .creditCard && !passesLuhn(text) { continue }
                    matches.append(SensitiveMatch(kind: kind, text: text, boundingBox: line.boundingBox))
                }
            }
        }
        return matches
    }

    /// Luhn checksum keeps random digit runs from being flagged as cards.
    private func passesLuhn(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count >= 13 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let (index, digit) = pair
            if index % 2 == 1 {
                let doubled = digit * 2
                return total + (doubled > 9 ? doubled - 9 : doubled)
            }
            return total + digit
        }
        return sum % 10 == 0
    }
}
