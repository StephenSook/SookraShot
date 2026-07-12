import Foundation

/// Formats RGB components (0...1) as a `#RRGGBB` hex string.
public enum HexColor {
    public static func string(red: Double, green: Double, blue: Double) -> String {
        func channel(_ value: Double) -> Int {
            max(0, min(255, Int((value * 255).rounded())))
        }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}
