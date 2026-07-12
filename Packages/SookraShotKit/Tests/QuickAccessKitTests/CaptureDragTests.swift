import AppKit
import CoreGraphics
import Foundation
import SharedKit
import Testing
@testable import QuickAccessKit

@Suite struct CaptureDragTests {
    /// A 12x8 opaque test image.
    private static func makeCapture() -> DeliveredCapture {
        let width = 12, height = 8
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return DeliveredCapture(image: context.makeImage()!)
    }

    /// The drag advertises all three types a real drop target might want: a file
    /// URL (Finder/folders/upload wells), inline PNG, and inline TIFF (text and
    /// compose views). This is the content that makes a drop actually land.
    @Test func writerAdvertisesFileURLAndImageData() throws {
        let writer = try #require(CaptureDrag.makeWriter(for: Self.makeCapture()))
        let types = writer.writableTypes(for: .general)
        #expect(types.contains(.fileURL))
        #expect(types.contains(.png))
        #expect(types.contains(.tiff))
    }

    /// The inline PNG representation is real PNG bytes (0x89 P N G signature).
    @Test func pngPropertyListIsRealPNG() throws {
        let writer = try #require(CaptureDrag.makeWriter(for: Self.makeCapture()))
        let png = try #require(writer.pasteboardPropertyList(forType: .png) as? Data)
        #expect(png.count > 8)
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        #expect(NSImage(data: png)?.isValid == true)
    }

    /// The inline TIFF representation decodes to an image.
    @Test func tiffPropertyListDecodes() throws {
        let writer = try #require(CaptureDrag.makeWriter(for: Self.makeCapture()))
        let tiff = try #require(writer.pasteboardPropertyList(forType: .tiff) as? Data)
        #expect(NSImage(data: tiff)?.isValid == true)
    }

    /// The file URL points at a real, sensibly-named .png on disk whose bytes
    /// decode back to the captured pixel dimensions.
    @Test func fileURLIsWrittenPNGWithRightSize() throws {
        let writer = try #require(CaptureDrag.makeWriter(for: Self.makeCapture()))
        defer { try? FileManager.default.removeItem(at: writer.fileURL) }
        #expect(writer.fileURL.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: writer.fileURL.path))
        #expect(writer.pasteboardPropertyList(forType: .fileURL) != nil)

        let source = try #require(CGImageSourceCreateWithURL(writer.fileURL as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 12)
        #expect(decoded.height == 8)
    }
}
