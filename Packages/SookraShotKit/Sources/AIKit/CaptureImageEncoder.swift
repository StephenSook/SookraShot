import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales (if needed) and PNG-encodes a capture to base64 for the vision
/// request. Capping the long edge keeps upload size and image-token cost sane
/// while staying legible for text-heavy captures.
enum CaptureImageEncoder {
    static func base64PNG(from image: CGImage, maxLongEdge: Int = 2000) -> String? {
        let source = downscale(image, maxLongEdge: maxLongEdge) ?? image
        guard let data = pngData(from: source) else { return nil }
        return data.base64EncodedString()
    }

    private static func downscale(_ image: CGImage, maxLongEdge: Int) -> CGImage? {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return nil }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
