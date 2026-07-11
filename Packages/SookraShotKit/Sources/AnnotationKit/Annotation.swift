import CoreGraphics
import Foundation

/// RGBA color that stays Sendable/Codable across module boundaries.
public struct RGBAColor: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let annotationRed = RGBAColor(red: 1.0, green: 0.23, blue: 0.19)
    public static let highlighterYellow = RGBAColor(red: 1.0, green: 0.92, blue: 0.23, alpha: 0.45)

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// One vector annotation. Coordinates are in image pixel space, origin bottom-left.
public struct Annotation: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case arrow
        case rect
        case filledRect
        case ellipse
        case line
        case text(String)
        case pencil([CGPoint])
        case highlighter([CGPoint])
        case counter(Int)
        case blur
        case pixelate
    }

    public let id: UUID
    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint
    public var color: RGBAColor
    public var strokeWidth: CGFloat
    public var fontSize: CGFloat

    public init(
        kind: Kind,
        start: CGPoint,
        end: CGPoint,
        color: RGBAColor = .annotationRed,
        strokeWidth: CGFloat = 6,
        fontSize: CGFloat = 40
    ) {
        self.id = UUID()
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
    }

    public var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
