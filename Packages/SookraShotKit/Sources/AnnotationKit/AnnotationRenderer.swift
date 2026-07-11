import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws annotations into a CGContext (canvas preview and flatten-export share this).
/// All coordinates are image pixel space, origin bottom-left.
public struct AnnotationRenderer {
    public init() {}

    // MARK: - Flatten

    /// Renders base image + annotations into a new CGImage for export.
    public func flatten(_ document: AnnotationDocument) -> CGImage? {
        let size = document.imageSize
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(document.baseImage, in: CGRect(origin: .zero, size: size))
        draw(document.annotations, of: document, in: context)
        return context.makeImage()
    }

    // MARK: - Draw

    public func draw(_ annotations: [Annotation], of document: AnnotationDocument, in context: CGContext) {
        for annotation in annotations {
            switch annotation.kind {
            case .blur:
                drawFilteredRegion(annotation, base: document.baseImage, in: context, pixelate: false)
            case .pixelate:
                drawFilteredRegion(annotation, base: document.baseImage, in: context, pixelate: true)
            default:
                drawVector(annotation, in: context)
            }
        }
    }

    private func drawVector(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
        case .arrow:
            drawArrow(annotation, in: context)
        case .rect:
            context.stroke(annotation.boundingRect)
        case .filledRect:
            context.fill(annotation.boundingRect)
        case .ellipse:
            context.strokeEllipse(in: annotation.boundingRect)
        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()
        case .text(let string):
            drawText(string, for: annotation, in: context)
        case .pencil(let points):
            strokePath(points, in: context)
        case .highlighter(let points):
            context.setLineWidth(annotation.fontSize * 0.6)
            strokePath(points, in: context)
        case .counter(let number):
            drawCounter(number, for: annotation, in: context)
        case .blur, .pixelate:
            break
        }
    }

    private func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func drawArrow(_ annotation: Annotation, in context: CGContext) {
        let start = annotation.start
        let end = annotation.end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(annotation.strokeWidth * 4, 18)
        let headAngle: CGFloat = .pi / 7

        // Shaft stops short of the tip so the head stays crisp.
        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * headLength * 0.6,
            y: end.y - sin(angle) * headLength * 0.6
        )
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        let left = CGPoint(
            x: end.x - cos(angle - headAngle) * headLength,
            y: end.y - sin(angle - headAngle) * headLength
        )
        let right = CGPoint(
            x: end.x - cos(angle + headAngle) * headLength,
            y: end.y - sin(angle + headAngle) * headLength
        )
        context.move(to: end)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()
    }

    private func drawText(_ string: String, for annotation: Annotation, in context: CGContext) {
        guard !string.isEmpty else { return }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
            .foregroundColor: NSColor(
                srgbRed: annotation.color.red,
                green: annotation.color.green,
                blue: annotation.color.blue,
                alpha: annotation.color.alpha
            ),
        ]
        string.draw(at: annotation.start, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCounter(_ number: Int, for annotation: Annotation, in context: CGContext) {
        let radius = max(annotation.fontSize * 0.6, 20)
        let center = annotation.start
        let circle = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fillEllipse(in: circle)

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let text = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFilteredRegion(
        _ annotation: Annotation,
        base: CGImage,
        in context: CGContext,
        pixelate: Bool
    ) {
        let region = annotation.boundingRect.integral
        guard region.width > 2, region.height > 2 else { return }

        // CGImage cropping uses top-left origin; annotation space is bottom-left.
        let cropRect = CGRect(
            x: region.minX,
            y: CGFloat(base.height) - region.maxY,
            width: region.width,
            height: region.height
        )
        guard let cropped = base.cropping(to: cropRect) else { return }

        let input = CIImage(cgImage: cropped)
        let output: CIImage?
        if pixelate {
            let filter = CIFilter.pixellate()
            filter.inputImage = input
            filter.scale = Float(max(region.width, region.height) / 14)
            output = filter.outputImage
        } else {
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input
            filter.radius = 14
            output = filter.outputImage?.cropped(to: input.extent)
        }
        guard let output,
              let rendered = CIContext().createCGImage(output, from: input.extent) else { return }

        context.saveGState()
        context.clip(to: region)
        context.draw(rendered, in: region)
        context.restoreGState()
    }
}
