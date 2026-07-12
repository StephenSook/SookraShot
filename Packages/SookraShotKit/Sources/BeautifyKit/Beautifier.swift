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

/// Optional window chrome drawn around the capture.
public enum BeautifyFrame: String, Sendable, CaseIterable {
    case none
    case macWindow
    case browser

    public var title: String {
        switch self {
        case .none: "None"
        case .macWindow: "macOS window"
        case .browser: "Browser"
        }
    }
}

/// Composites a capture onto a padded gradient background with a shadow and
/// rounded corners, optionally inside a macOS/browser window frame.
public struct Beautifier: Sendable {
    public init() {}

    public func beautify(
        _ image: CGImage,
        background: BeautifyBackground,
        frame: BeautifyFrame = .none
    ) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let titleBarHeight: CGFloat = frame == .none ? 0 : max((width * 0.045).rounded(), 22)
        let addressBarHeight: CGFloat = frame == .browser ? (titleBarHeight * 0.85).rounded() : 0
        let chromeHeight = titleBarHeight + addressBarHeight

        let cardWidth = width
        let cardHeight = height + chromeHeight
        let padding = (max(cardWidth, cardHeight) * 0.09).rounded()
        let canvasWidth = Int(cardWidth + padding * 2)
        let canvasHeight = Int(cardHeight + padding * 2)
        let cornerRadius = min(width, height) * 0.028

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

        let cardRect = CGRect(x: padding, y: padding, width: cardWidth, height: cardHeight)
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Drop shadow, cast by an opaque rounded fill behind the card.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -padding * 0.22),
            blur: padding * 0.5,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        context.addPath(cardPath)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        // Card contents (image at the bottom, chrome above it), clipped to the card.
        context.saveGState()
        context.addPath(cardPath)
        context.clip()
        context.draw(image, in: CGRect(x: padding, y: padding, width: width, height: height))
        if frame != .none {
            drawChrome(
                in: context, frame: frame, colorSpace: colorSpace,
                cardX: padding, cardWidth: cardWidth,
                imageTop: padding + height, addressBarHeight: addressBarHeight, titleBarHeight: titleBarHeight
            )
        }
        context.restoreGState()

        return context.makeImage()
    }

    private func drawChrome(
        in context: CGContext,
        frame: BeautifyFrame,
        colorSpace: CGColorSpace,
        cardX: CGFloat,
        cardWidth: CGFloat,
        imageTop: CGFloat,
        addressBarHeight: CGFloat,
        titleBarHeight: CGFloat
    ) {
        let titleBarBottom = imageTop + addressBarHeight
        let titleBar = CGColor(colorSpace: colorSpace, components: [0.91, 0.91, 0.92, 1])!

        // Address bar (browser) with a white URL pill.
        if addressBarHeight > 0 {
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [0.95, 0.95, 0.96, 1])!)
            context.fill(CGRect(x: cardX, y: imageTop, width: cardWidth, height: addressBarHeight))
            let pillInsetX = titleBarHeight * 0.5
            let pillHeight = addressBarHeight * 0.55
            let pill = CGRect(
                x: cardX + pillInsetX,
                y: imageTop + (addressBarHeight - pillHeight) / 2,
                width: cardWidth - pillInsetX * 2,
                height: pillHeight
            )
            context.addPath(CGPath(roundedRect: pill, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
        }

        // Title bar with traffic lights.
        context.setFillColor(titleBar)
        context.fill(CGRect(x: cardX, y: titleBarBottom, width: cardWidth, height: titleBarHeight))

        let radius = titleBarHeight * 0.15
        let centerY = titleBarBottom + titleBarHeight / 2
        let spacing = titleBarHeight * 0.5
        let firstX = cardX + titleBarHeight * 0.6
        let lights = [
            CGColor(colorSpace: colorSpace, components: [1.0, 0.37, 0.34, 1])!,
            CGColor(colorSpace: colorSpace, components: [1.0, 0.74, 0.18, 1])!,
            CGColor(colorSpace: colorSpace, components: [0.16, 0.78, 0.25, 1])!,
        ]
        for (index, color) in lights.enumerated() {
            let centerX = firstX + CGFloat(index) * spacing
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
        }
    }
}
