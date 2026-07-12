import CoreGraphics
import Foundation

/// Background gradient presets for beautified screenshots.
public enum BeautifyBackground: String, Sendable, CaseIterable {
    case sunset
    case ocean
    case mint
    case graphite
    case snow

    public var title: String {
        switch self {
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .mint: "Mint"
        case .graphite: "Graphite"
        case .snow: "Snow"
        }
    }

    /// (start, end) RGB stops in 0...1.
    var colors: (start: (CGFloat, CGFloat, CGFloat), end: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .sunset: ((1.0, 0.49, 0.37), (0.996, 0.71, 0.48))
        case .ocean: ((0.13, 0.58, 0.69), (0.43, 0.84, 0.93))
        case .mint: ((0.26, 0.91, 0.48), (0.22, 0.98, 0.84))
        case .graphite: ((0.14, 0.15, 0.16), (0.27, 0.28, 0.29))
        case .snow: ((1.0, 1.0, 1.0), (0.89, 0.90, 0.93))
        }
    }
}

/// Composites a capture onto a padded gradient background with a shadow and
/// rounded corners, for sharing on social/chat.
public struct Beautifier: Sendable {
    public init() {}

    public func beautify(_ image: CGImage, background: BeautifyBackground) -> CGImage? {
        let width = image.width
        let height = image.height
        let padding = Int((CGFloat(max(width, height)) * 0.09).rounded())
        let canvasWidth = width + padding * 2
        let canvasHeight = height + padding * 2
        let cornerRadius = CGFloat(min(width, height)) * 0.028

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: canvasWidth, height: canvasHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let stops = background.colors
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: [stops.start.0, stops.start.1, stops.start.2, 1])!,
                CGColor(colorSpace: colorSpace, components: [stops.end.0, stops.end.1, stops.end.2, 1])!,
            ] as CFArray,
            locations: [0, 1]
        ) else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: canvasHeight),
            end: CGPoint(x: canvasWidth, y: 0),
            options: []
        )

        let imageRect = CGRect(x: padding, y: padding, width: width, height: height)
        let roundedPath = CGPath(
            roundedRect: imageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
        )

        // Drop shadow, cast by an opaque rounded fill behind the image.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -CGFloat(padding) * 0.22),
            blur: CGFloat(padding) * 0.5,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        context.addPath(roundedPath)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // Rounded-corner capture on top.
        context.saveGState()
        context.addPath(roundedPath)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()

        return context.makeImage()
    }
}
