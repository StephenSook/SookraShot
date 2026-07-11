import CoreGraphics
import Foundation
import ImageIO
import SharedKit
import UniformTypeIdentifiers

/// Encodes CGImage to on-disk formats via ImageIO.
public struct ImageEncoder: Sendable {
    public init() {}

    public func data(from image: CGImage, format: ImageFormat) -> Data? {
        let type: UTType
        switch format {
        case .png: type = .png
        case .jpeg: type = .jpeg
        case .heic: type = .heic
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
