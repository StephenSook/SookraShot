import Foundation

/// Expands capture filename templates.
///
/// Tokens: `%y` year, `%m` month, `%d` day, `%H` hour, `%M` minute, `%S` second,
/// `%i` auto-increment counter (removed when no counter is supplied).
public struct FilenameTemplate: Sendable, Equatable {
    public static let `default` = FilenameTemplate(pattern: "SookraShot %y-%m-%d at %H.%M.%S")

    public var pattern: String

    public init(pattern: String) {
        self.pattern = pattern
    }

    public func filename(for date: Date, counter: Int? = nil, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, width: Int = 2) -> String {
            String(format: "%0\(width)d", value ?? 0)
        }
        var result = pattern
        let substitutions: [(String, String)] = [
            ("%y", pad(parts.year, width: 4)),
            ("%m", pad(parts.month)),
            ("%d", pad(parts.day)),
            ("%H", pad(parts.hour)),
            ("%M", pad(parts.minute)),
            ("%S", pad(parts.second)),
            ("%i", counter.map(String.init) ?? ""),
        ]
        for (token, value) in substitutions {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
