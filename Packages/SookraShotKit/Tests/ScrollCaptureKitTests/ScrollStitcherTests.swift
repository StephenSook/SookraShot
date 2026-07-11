import CoreGraphics
import Foundation
import Testing
@testable import ScrollCaptureKit

@Suite struct ScrollStitcherTests {
    /// Deterministic tall test pattern: every row gets a distinct busy pattern
    /// from a seeded LCG, so overlap detection has real signal.
    private static func makeTallImage(width: Int, height: Int) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var state: UInt64 = 0x2545F4914F6CDD1D
        for row in 0..<height {
            var rowSeed = state &+ UInt64(row) &* 0x9E3779B97F4A7C15
            for col in 0..<width {
                rowSeed = rowSeed &* 6364136223846793005 &+ 1442695040888963407
                let value = UInt8(truncatingIfNeeded: rowSeed >> 33)
                let base = (row * width + col) * 4
                pixels[base] = value
                pixels[base + 1] = value &+ UInt8(truncatingIfNeeded: row)
                pixels[base + 2] = value ^ UInt8(truncatingIfNeeded: col)
                pixels[base + 3] = 255
            }
        }
        state &+= 1
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Viewport of `tall` starting at row `top` (top-left origin), `height` rows.
    private static func window(of tall: CGImage, top: Int, height: Int) -> CGImage {
        tall.cropping(to: CGRect(x: 0, y: top, width: tall.width, height: height))!
    }

    @Test func stitchesOverlappingScrollFrames() {
        let tall = Self.makeTallImage(width: 400, height: 1100)
        let stitcher = ScrollStitcher()
        stitcher.start(with: Self.window(of: tall, top: 0, height: 600))

        let second = stitcher.append(Self.window(of: tall, top: 250, height: 600))
        #expect(second == .appended(newRows: 250))

        let third = stitcher.append(Self.window(of: tall, top: 500, height: 600))
        #expect(third == .appended(newRows: 250))

        let composite = stitcher.finish()
        #expect(composite?.width == 400)
        #expect(composite?.height == 1100)
    }

    @Test func stitchedPixelsMatchOriginal() {
        let tall = Self.makeTallImage(width: 300, height: 900)
        let stitcher = ScrollStitcher()
        stitcher.start(with: Self.window(of: tall, top: 0, height: 500))
        _ = stitcher.append(Self.window(of: tall, top: 200, height: 500))
        _ = stitcher.append(Self.window(of: tall, top: 400, height: 500))

        let composite = stitcher.finish()!
        #expect(composite.height == 900)

        let original = GrayscaleImage(image: tall)!
        let stitched = GrayscaleImage(image: composite)!
        // Sample rows across the full height, including seam areas.
        for row in [0, 250, 499, 500, 650, 899] {
            for col in [0, 150, 299] {
                let expected = original.pixels[row * 300 + col]
                let actual = stitched.pixels[row * 300 + col]
                #expect(abs(Int(expected) - Int(actual)) <= 2, "mismatch at row \(row) col \(col)")
            }
        }
    }

    @Test func identicalFrameReportsNoNewContent() {
        let tall = Self.makeTallImage(width: 200, height: 600)
        let frame = Self.window(of: tall, top: 0, height: 400)
        let stitcher = ScrollStitcher()
        stitcher.start(with: frame)
        #expect(stitcher.append(frame) == .noNewContent)
        #expect(stitcher.finish()?.height == 400)
    }

    @Test func unrelatedFrameReportsLowConfidence() {
        let tallA = Self.makeTallImage(width: 200, height: 600)
        // Solid-color frame shares no structure with the pattern.
        var solid = [UInt8](repeating: 128, count: 200 * 400 * 4)
        for index in stride(from: 3, to: solid.count, by: 4) { solid[index] = 255 }
        let provider = CGDataProvider(data: Data(solid) as CFData)!
        let unrelated = CGImage(
            width: 200, height: 400, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 200 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!

        let stitcher = ScrollStitcher()
        stitcher.start(with: Self.window(of: tallA, top: 0, height: 400))
        #expect(stitcher.append(unrelated) == .lowConfidence)
    }
}
