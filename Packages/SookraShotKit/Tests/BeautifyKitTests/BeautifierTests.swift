import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BeautifyKit

@Suite struct BeautifierTests {
    @Test func beautifyPadsAndPreservesAspect() throws {
        let source = Self.makeTestImage(width: 400, height: 250)
        let output = try #require(Beautifier().beautify(source, background: .ocean))

        // Padding is 9% of the long edge on each side.
        let pad = Int((400.0 * 0.09).rounded())
        #expect(output.width == 400 + pad * 2)
        #expect(output.height == 250 + pad * 2)

        // Write a preview for manual inspection.
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("sookrashot-beautify-preview.png")
        try Self.writePNG(output, to: previewURL)
        #expect(FileManager.default.fileExists(atPath: previewURL.path))
    }

    @Test func rendersWindowAndBrowserFrames() throws {
        let source = Self.makeTestImage(width: 600, height: 380)
        for frame in [BeautifyFrame.macWindow, .browser] {
            let output = try #require(Beautifier().beautify(source, background: .graphite, frame: frame))
            // Frame adds chrome height above the image.
            #expect(output.height > 380 + Int(600.0 * 0.09) * 2)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("sookrashot-frame-\(frame.rawValue).png")
            try Self.writePNG(output, to: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    private static func makeTestImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.30, green: 0.68, blue: 1.0, alpha: 1))
        context.fill(CGRect(x: 40, y: height / 2 - 20, width: width - 80, height: 40))
        return context.makeImage()!
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        try (data as Data).write(to: url)
    }
}
